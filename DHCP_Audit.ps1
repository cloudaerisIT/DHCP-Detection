#Requires -Version 5.1
#===========================================================================
# DHCP Detection Script for MECM / Configuration Manager
# Logs DHCP status per adapter to a central file share.
#
# Usage: Deploy as a Script or Package/Program in MECM.
# Run As: System account (or an account with write access to $LogShare)
#===========================================================================

#region --- CONFIGURATION ---
$LogShare   = '\\fileserver\MECM_Logs\DHCP_Audit'  # Update to your UNC path
$LogFile    = Join-Path $LogShare "DHCP_$($env:COMPUTERNAME)_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
$MaxAgeDays = 90   # Logs older than this will be pruned on each run
#endregion

#region --- FUNCTIONS ---
function Write-Log {
    param([string]$Message, [string]$Level = 'INFO')
    $entry = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [$Level] $Message"
    Add-Content -Path $LogFile -Value $entry -Encoding UTF8
    Write-Output $entry
}

function Get-DHCPStatus {
    # Returns an array of objects - one per active IP-enabled adapter
    $adapters = Get-WmiObject -Class Win32_NetworkAdapterConfiguration `
                    -Filter "IPEnabled = True"

    foreach ($adapter in $adapters) {
        [PSCustomObject]@{
            ComputerName    = $env:COMPUTERNAME
            AdapterIndex    = $adapter.Index
            AdapterDesc     = $adapter.Description
            DHCPEnabled     = $adapter.DHCPEnabled
            DHCPServer      = $adapter.DHCPServer
            IPAddresses     = ($adapter.IPAddress    -join ', ')
            SubnetMasks     = ($adapter.IPSubnet     -join ', ')
            DefaultGateway  = ($adapter.DefaultIPGateway -join ', ')
            LeaseObtained   = $adapter.DHCPLeaseObtained
            LeaseExpires    = $adapter.DHCPLeaseExpires
            CollectedAt     = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        }
    }
}

function Remove-OldLogs {
    param([string]$Path, [int]$Days)
    Get-ChildItem -Path $Path -Filter '*.log' |
        Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-$Days) } |
        Remove-Item -Force -ErrorAction SilentlyContinue
}
#endregion

#region --- MAIN ---
try {
    # Ensure the log share is reachable
    if (-not (Test-Path $LogShare)) {
        Write-Output "ERROR: Log share unreachable: $LogShare"
        exit 1
    }

    # Prune old logs before writing a new one
    Remove-OldLogs -Path $LogShare -Days $MaxAgeDays

    Write-Log "=== DHCP Audit Start: $env:COMPUTERNAME ==="
    Write-Log "OS: $(([System.Environment]::OSVersion).VersionString)"
    Write-Log "Domain: $env:USERDNSDOMAIN"

    $results = Get-DHCPStatus

    if ($results) {
        foreach ($r in $results) {
            $status = if ($r.DHCPEnabled) { 'DHCP' } else { 'STATIC' }
            Write-Log "Adapter [$($r.AdapterIndex)] $($r.AdapterDesc) | $status | IP: $($r.IPAddresses) | DHCP Server: $($r.DHCPServer)"
        }

        # Also write a flat CSV row to a shared aggregate file for reporting
        $CsvPath = Join-Path $LogShare "DHCPAudit_Aggregate.csv"
        $writeCsvHeader = -not (Test-Path $CsvPath)

        # Retry loop for CSV write (multiple machines may write concurrently)
        $retries = 3
        for ($i = 0; $i -lt $retries; $i++) {
            try {
                $results | Export-Csv -Path $CsvPath -Append -NoTypeInformation `
                    -Encoding UTF8 -ErrorAction Stop
                break
            } catch {
                Start-Sleep -Milliseconds (500 + (Get-Random -Maximum 500))
            }
        }

        Write-Log "Results appended to aggregate CSV."
    } else {
        Write-Log "No IP-enabled adapters found." 'WARN'
    }

    Write-Log "=== DHCP Audit Complete ==="
    exit 0
} catch {
    Write-Output "FATAL: $($_.Exception.Message)"
    try { Write-Log "FATAL: $($_.Exception.Message)" 'ERROR' } catch {}
    exit 1
}
#endregion

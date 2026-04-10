# DHCP Detection & Audit Script for MECM

A PowerShell script designed for deployment via Microsoft Endpoint Configuration Manager (MECM / ConfigMgr) that detects DHCP configuration status across all network adapters on managed endpoints and logs results to a central file share.

---

## Overview

When deployed through MECM, this script runs silently under the System account on each target machine, enumerates all IP-enabled network adapters, and writes structured output to a UNC log share. Each machine produces its own timestamped log file, and all results are also appended to a shared aggregate CSV suitable for fleet-wide reporting in Excel or Power BI.

---

## Features

- Detects DHCP vs. static IP configuration per adapter
- Captures DHCP server address, lease obtained/expiry, IP addresses, subnet masks, and default gateway
- Handles multi-homed machines (multiple adapters logged individually)
- Writes per-machine `.log` files and a shared aggregate `DHCPAudit_Aggregate.csv`
- Concurrent write safety via randomized back-off retry on the aggregate CSV
- Automatic pruning of log files older than a configurable threshold
- Clean exit codes (`0` = success, `1` = failure) for MECM status reporting

---

## Requirements

- PowerShell 5.1 or later
- MECM / Configuration Manager (for deployment)
- A writable UNC share accessible by managed machine accounts

---

## Configuration

Edit the two variables at the top of the script before deployment:

```powershell
$LogShare   = '\\fileserver\MECM_Logs\DHCP_Audit'  # UNC path to your log share
$MaxAgeDays = 90                                     # Retention period for per-machine .log files
```

---

## File Share Setup

Create the destination folder and configure permissions before deploying the script.

**NTFS and Share permissions required:**

| Principal | Permission |
|---|---|
| MECM Site Server computer account | Full Control |
| Target machine accounts (`DOMAIN\COMPUTERNAME$`) | Modify |
| Admins / reporting users | Read |

> The most common deployment failure is missing Modify permission for machine computer accounts. If scoping to a collection, consider a security group containing those computer objects.

---

## Deployment in MECM

**Option A — Scripts (recommended for ad-hoc audits)**

1. Navigate to **Administration > Scripts > Create Script**
2. Paste the script contents
3. Set **Run As:** System
4. Approve and deploy to the target collection

**Option B — Package / Program (for scheduled recurring audits)**

1. Create a Package pointing to the script file on a distribution point
2. Set the Program command line:
   ```
   powershell.exe -ExecutionPolicy Bypass -NoProfile -File DHCP_Audit.ps1
   ```
3. Set **Run As:** System account
4. Schedule via a recurring deployment or MECM Maintenance Window

---

## Output

**Per-machine log files**
```
\\fileserver\MECM_Logs\DHCP_Audit\DHCP_COMPUTERNAME_20250410_143022.log
```
Human-readable, one entry per adapter. Useful for investigating a specific machine.

**Aggregate CSV**
```
\\fileserver\MECM_Logs\DHCP_Audit\DHCPAudit_Aggregate.csv
```
All machines appended into a single file. Opens directly in Excel. Fields included:

| Field | Description |
|---|---|
| ComputerName | Hostname of the reporting machine |
| AdapterIndex | NIC index number |
| AdapterDesc | Adapter description string |
| DHCPEnabled | True / False |
| DHCPServer | IP address of the DHCP server (if applicable) |
| IPAddresses | Assigned IP address(es) |
| SubnetMasks | Associated subnet mask(s) |
| DefaultGateway | Default gateway address(es) |
| LeaseObtained | DHCP lease start time |
| LeaseExpires | DHCP lease expiry time |
| CollectedAt | Timestamp of data collection |

---

## Exit Codes

| Code | Meaning |
|---|---|
| 0 | Success |
| 1 | Log share unreachable or unhandled exception |

---

## Notes on Concurrency

When deploying to large collections, many machines may attempt to append to the aggregate CSV simultaneously. The script handles this with a 3-attempt retry loop using randomized back-off (500–1000ms delay between attempts). For very large deployments (500+ machines in a short collection window), consider switching to per-machine CSV files only and consolidating them via a scheduled task on the file server.

---

## Extending This Script

This script can be adapted into a **Configuration Item (CI)** in MECM if you need compliance reporting rather than just logging. The discovery script would return `$true` or `$false` based on whether DHCP is enabled, and MECM would surface non-compliant machines in the Compliance dashboard. Open an issue or submit a PR if you'd like that variation added to this repo.

---

## License

MIT License. See `LICENSE` for details.

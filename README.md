# Windows System Information Tool

A modular, zero dependency PowerShell diagnostic and inventory auditing tool for IT administrators, MSPs, and helpdesk teams. Designed for high performance, terminal scannability, and cross version compatibility.

---

## Key Features

* **Zero External Dependencies:** Built natively using Windows CIM/WMI wrappers and core PowerShell cmdlets.
* **Cross Version Compatibility:** Fully supports both **PowerShell 5.1** and **PowerShell 7+** environments without throw errors on date conversions or WMI namespace differences.
* **Security & Compliance Auditing:** Checks TPM chip readiness, BitLocker status, Windows Defender/AV registration, pending reboots, and local administrator membership.
* **Hardware Specs:** Detailed breakdown of physical RAM slots, storage drives (SMART status + volume usage), CPU core counts, and system battery charge (laptops).
* **Remote Management Ready:** Native `-RemoteComputer` support to execute remote audits via WinRM (`Invoke-Command`).
* **Structured Exporting:** Optional `-ExportJsonPath` parameter to write inventory reports into JSON objects for RMM logging or reporting.

---

## Usage Examples

### 1. Basic Local Audit
Run locally within standard or elevated PowerShell terminals:
```powershell
.\SystemInfo.ps1
2. Audit Remote Endpoint
Execute remotely against a target endpoint on the network (requires WinRM enabled):

PowerShell
.\SystemInfo.ps1 -RemoteComputer "DESKTOP-FINANCE01"
3. Audit Local Endpoint & Export JSON Report
Run locally and output the structured result object to a log file:

PowerShell
.\SystemInfo.ps1 -ExportJsonPath "C:\Logs\AssetReport.json"
Technical Standards
Elevation Awareness: Detects shell privilege level dynamically. Gracefully skips privileged commands (e.g., BitLocker query) when run in non-elevated shells without throwing terminal errors.

Safe Date Handling: Safely parses legacy WMI strings and standard [DateTime] objects returned by Get-CimInstance across Windows versions.

Server OS Fallbacks: Automatically inspects the WinDefend service on Server editions where root\SecurityCenter2 WMI namespaces are absent.

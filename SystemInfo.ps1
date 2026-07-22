<#
.SYNOPSIS
    Gathers detailed hardware specifications, OS details, disk health, and BitLocker status.
.DESCRIPTION
    Provides a quick inventory report for IT administrators. Supports local execution or remote 
    querying via WinRM, as well as JSON export functionality.
.PARAMETER RemoteComputer
    Optional hostname or IP to run the inventory against remotely using Invoke-Command.
.PARAMETER ExportJsonPath
    Optional file path to export structured system inventory data as a JSON file.
.EXAMPLE
    .\Get-WorkstationInventory.ps1
.EXAMPLE
    .\Get-WorkstationInventory.ps1 -RemoteComputer "WORKSTATION01" -ExportJsonPath "C:\Logs\HWReport.json"
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory = $false)]
    [string]$RemoteComputer,

    [Parameter(Mandatory = $false)]
    [string]$ExportJsonPath
)

# Wrapper function for execution
function Invoke-WorkstationInventory {
    [CmdletBinding()]
    param ()

    # Check elevation status
    $IsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

    # Cross-version CIM/WMI wrapper
    function Get-SafeCimInstance {
        param ([string]$ClassName, [string]$Namespace = 'root\cimv2')
        try {
            Get-CimInstance -ClassName $ClassName -Namespace $Namespace -ErrorAction Stop
        } catch {
            $null
        }
    }

    Write-Host "`n=================================================" -ForegroundColor Cyan
    Write-Host "     WORKSTATION HARDWARE & ASSET INVENTORY      " -ForegroundColor Cyan
    if (-not $IsAdmin) {
        Write-Host "      [ Running in Non-Elevated Mode ]          " -ForegroundColor DarkGray
    }
    Write-Host "=================================================`n" -ForegroundColor Cyan

    # ------------------------------------------------------------------------------
    # 1. SYSTEM IDENTIFICATION & BIOS
    # ------------------------------------------------------------------------------
    Write-Host "[1/5] System & BIOS Specifications:" -ForegroundColor Yellow

    $ComputerSystem = Get-SafeCimInstance -ClassName "Win32_ComputerSystem"
    $Bios           = Get-SafeCimInstance -ClassName "Win32_BIOS"
    $OS             = Get-SafeCimInstance -ClassName "Win32_OperatingSystem"

    $MakeModel = if ($ComputerSystem) { "$($ComputerSystem.Manufacturer) $($ComputerSystem.Model)" } else { "Unknown" }
    $Serial    = if ($Bios) { $Bios.SerialNumber } else { "Unknown" }

    # Robust ReleaseDate conversion
    $BiosDate = if ($Bios.ReleaseDate) {
        if ($Bios.ReleaseDate -is [datetime]) {
            " (Released: $($Bios.ReleaseDate.ToString('yyyy-MM-dd')))"
        } else {
            try {
                " (Released: $([Management.ManagementDateTimeConverter]::ToDateTime($Bios.ReleaseDate).ToString('yyyy-MM-dd')))"
            } catch { "" }
        }
    } else { "" }

    $BiosVer = if ($Bios) { "$($Bios.SMBIOSBIOSVersion)$BiosDate" } else { "Unknown" }
    $OSName  = if ($OS) { "$($OS.Caption) ($($OS.OSArchitecture))" } else { "Unknown" }
    $OSBuild = if ($OS) { "$($OS.Version) (Build $($OS.BuildNumber))" } else { "Unknown" }

    $Uptime = if ($OS.LastBootUpTime) { 
        $BootTime = $OS.LastBootUpTime
        $Span     = (Get-Date) - $BootTime
        "{0}d {1}h {2}m" -f $Span.Days, $Span.Hours, $Span.Minutes
    } else { "Unknown" }

    Write-Host "  * Hostname      : $env:COMPUTERNAME" -ForegroundColor White
    Write-Host "  * Make / Model  : $MakeModel" -ForegroundColor Gray
    Write-Host "  * Serial Number : $Serial" -ForegroundColor Gray
    Write-Host "  * BIOS Version  : $BiosVer" -ForegroundColor Gray
    Write-Host "  * Operating Sys : $OSName" -ForegroundColor Gray
    Write-Host "  * OS Build      : $OSBuild" -ForegroundColor Gray
    Write-Host "  * System Uptime : $Uptime" -ForegroundColor Gray

    # Battery Check (Mobile Devices)
    $Battery = Get-SafeCimInstance -ClassName "Win32_Battery"
    if ($Battery) {
        $Charge = if ($Battery.EstimatedChargeRemaining) { "$($Battery.EstimatedChargeRemaining)%" } else { "Unknown" }
        Write-Host "  * Battery Status: $Charge Remaining" -ForegroundColor White
    }

    # ------------------------------------------------------------------------------
    # 2. PROCESSOR & MEMORY (RAM) AUDIT
    # ------------------------------------------------------------------------------
    Write-Host "`n[2/5] Processor & RAM Specs:" -ForegroundColor Yellow

    $Processor = Get-SafeCimInstance -ClassName "Win32_Processor" | Select-Object -First 1
    $RAMChips  = Get-SafeCimInstance -ClassName "Win32_PhysicalMemory"

    if ($Processor) {
        Write-Host "  * CPU Model     : $($Processor.Name.Trim())" -ForegroundColor White
        Write-Host "    Cores/Threads : $($Processor.NumberOfCores) Cores / $($Processor.NumberOfLogicalProcessors) Threads" -ForegroundColor Gray
    }

    $TotalRAMGB = 0
    if ($RAMChips) {
        $TotalRAMGB  = [math]::Round(($RAMChips | Measure-Object -Property Capacity -Sum).Sum / 1GB, 2)
        $SlotCount   = $RAMChips.Count
        $RAMSpeed    = ($RAMChips | Select-Object -First 1).Speed
        
        Write-Host "  * Installed RAM : ${TotalRAMGB} GB ($SlotCount Slot(s) Populated @ ${RAMSpeed} MHz)" -ForegroundColor White
        foreach ($Chip in $RAMChips) {
            $ChipGB = [math]::Round($Chip.Capacity / 1GB, 2)
            $Vendor = if ($Chip.Manufacturer) { $Chip.Manufacturer.Trim() } else { "Generic" }
            Write-Host "    - $($Chip.DeviceLocator): ${ChipGB} GB ($Vendor - $($Chip.Speed) MHz)" -ForegroundColor Gray
        }
    } else {
        Write-Host "  * Installed RAM : Unable to query RAM hardware" -ForegroundColor Red
    }

    # ------------------------------------------------------------------------------
    # 3. STORAGE & DISK HEALTH (SMART) AUDIT
    # ------------------------------------------------------------------------------
    Write-Host "`n[3/5] Storage Drives & Disk Health:" -ForegroundColor Yellow

    $PhysicalDisks = Get-PhysicalDisk -ErrorAction SilentlyContinue
    $LogicalDisks  = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DriveType=3" -ErrorAction SilentlyContinue

    if ($PhysicalDisks) {
        foreach ($Disk in $PhysicalDisks) {
            $SizeGB      = [math]::Round($Disk.Size / 1GB, 2)
            $HealthColor = if ($Disk.HealthStatus -eq 'Healthy') { "Green" } else { "Red" }
            Write-Host "  * Physical Drive : $($Disk.FriendlyName) (${SizeGB} GB - $($Disk.MediaType))" -ForegroundColor White
            Write-Host "    Health Status  : $($Disk.HealthStatus) (Operational: $($Disk.OperationalStatus))" -ForegroundColor $HealthColor
        }
    } else {
        $Disks = Get-Disk -ErrorAction SilentlyContinue
        foreach ($D in $Disks) {
            $SizeGB = [math]::Round($D.Size / 1GB, 2)
            Write-Host "  * Disk ($($D.Number))       : $($D.FriendlyName) (${SizeGB} GB)" -ForegroundColor White
        }
    }

    if ($LogicalDisks) {
        Write-Host "`n  Volume Usage:" -ForegroundColor White
        foreach ($Drive in $LogicalDisks) {
            $TotalGB = [math]::Round($Drive.Size / 1GB, 2)
            $FreeGB  = [math]::Round($Drive.FreeSpace / 1GB, 2)
            $FreePct = [math]::Round(($FreeGB / $TotalGB) * 100, 1)
            
            $SpaceColor = if ($FreePct -lt 15) { "Red" } else { "Gray" }
            Write-Host "    - Volume $($Drive.DeviceID) ($($Drive.VolumeName)) : $FreeGB GB free of $TotalGB GB ($FreePct% free)" -ForegroundColor $SpaceColor
        }
    }

    # ------------------------------------------------------------------------------
    # 4. SECURITY, REBOOT & ENCRYPTION POSTURE
    # ------------------------------------------------------------------------------
    Write-Host "`n[4/5] Security & Compliance Posture:" -ForegroundColor Yellow

    # Pending Reboot Check
    $PendingReboot = [bool]((Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending" -ErrorAction SilentlyContinue) -or
                     (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired" -ErrorAction SilentlyContinue))
    $RebootStatus = if ($PendingReboot) { "PENDING REBOOT" } else { "No Reboot Pending" }
    $RebootColor  = if ($PendingReboot) { "Yellow" } else { "Green" }
    Write-Host "  * Pending Reboot: $RebootStatus" -ForegroundColor $RebootColor

    # BitLocker Status
    $BitLockerStatus = "Unknown"
    if ($IsAdmin) {
        try {
            $BitLocker = Get-BitLockerVolume -MountPoint "C:" -ErrorAction Stop
            $BitLockerStatus = if ($BitLocker.ProtectionStatus -eq 'On') { "ENCRYPTED (On)" } else { "UNENCRYPTED (Off)" }
            $BLColor          = if ($BitLocker.ProtectionStatus -eq 'On') { "Green" } else { "Red" }
            
            Write-Host "  * BitLocker (C:) : $BitLockerStatus - Method: $($BitLocker.EncryptionMethod)" -ForegroundColor $BLColor
        } catch {
            Write-Host "  * BitLocker (C:) : Unable to query or not configured" -ForegroundColor Red
        }
    } else {
        Write-Host "  * BitLocker (C:) : SKIPPED (Requires Administrator privileges)" -ForegroundColor DarkGray
    }

    # TPM Status
    try {
        $TPM = Get-Tpm -ErrorAction Stop
        $TPMStatus = if ($TPM.TpmPresent -and $TPM.TpmReady) { "PRESENT & READY" } else { "NOT READY / DISABLED" }
        $TPMColor  = if ($TPM.TpmPresent -and $TPM.TpmReady) { "Green" } else { "Yellow" }
        Write-Host "  * TPM Chip      : $TPMStatus" -ForegroundColor $TPMColor
    } catch {
        Write-Host "  * TPM Chip      : Unable to query (Requires Elevation or unsupported OS)" -ForegroundColor DarkGray
    }

    # Active Antivirus Audit
    $AV = Get-CimInstance -Namespace "root\SecurityCenter2" -ClassName "AntivirusProduct" -ErrorAction SilentlyContinue
    $RegisteredAV = "None Detected"
    if ($AV) {
        $RegisteredAV = ($AV.displayName) -join ", "
        Write-Host "  * Registered AV : $RegisteredAV" -ForegroundColor Green
    } else {
        $DefendSvc = Get-Service -Name "WinDefend" -ErrorAction SilentlyContinue
        if ($DefendSvc -and $DefendSvc.Status -eq 'Running') {
            $RegisteredAV = "Microsoft Defender Antivirus (Service Active)"
            Write-Host "  * Registered AV : $RegisteredAV" -ForegroundColor Green
        } else {
            Write-Host "  * Registered AV : None Detected or Service Stopped" -ForegroundColor Yellow
        }
    }

    # Local Administrators Group
    $LocalAdmins = Get-LocalGroupMember -Group "Administrators" -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name
    if ($LocalAdmins) {
        Write-Host "  * Local Admins  : $($LocalAdmins -join ', ')" -ForegroundColor Gray
    }

    # ------------------------------------------------------------------------------
    # 5. RESOURCE USAGE & TOP PROCESSES
    # ------------------------------------------------------------------------------
    Write-Host "`n[5/5] Top Resource-Consuming Processes:" -ForegroundColor Yellow

    $TopCPU = Get-Process | Where-Object { $_.CPU } | Sort-Object CPU -Descending | Select-Object -First 3
    $TopRAM = Get-Process | Sort-Object WorkingSet64 -Descending | Select-Object -First 3

    Write-Host "  * Top CPU Consumers:" -ForegroundColor White
    foreach ($Proc in $TopCPU) {
        $CPUVal = [math]::Round($Proc.CPU, 1)
        Write-Host "    - $($Proc.ProcessName) (PID: $($Proc.Id)) -> Total CPU Time: ${CPUVal}s" -ForegroundColor Gray
    }

    Write-Host "  * Top RAM Consumers:" -ForegroundColor White
    foreach ($Proc in $TopRAM) {
        $RAMMB = [math]::Round($Proc.WorkingSet64 / 1MB, 1)
        Write-Host "    - $($Proc.ProcessName) (PID: $($Proc.Id)) -> Memory Usage: ${RAMMB} MB" -ForegroundColor Gray
    }

    Write-Host "`n=================================================" -ForegroundColor Cyan
    Write-Host "Inventory Complete." -ForegroundColor Cyan

    # Return Structured Object for Logging/Export
    return [PSCustomObject]@{
        Timestamp        = (Get-Date).ToString("o")
        Hostname         = $env:COMPUTERNAME
        ManufacturerModel= $MakeModel
        SerialNumber     = $Serial
        BIOSVersion      = $BiosVer
        OperatingSystem  = $OSName
        OSBuild          = $OSBuild
        Uptime           = $Uptime
        CPU              = if ($Processor) { $Processor.Name.Trim() } else { "Unknown" }
        TotalRAM_GB      = $TotalRAMGB
        PendingReboot    = $PendingReboot
        BitLockerStatus  = $BitLockerStatus
        RegisteredAV     = $RegisteredAV
        LocalAdmins      = ($LocalAdmins -join ", ")
    }
}

# Main Script Execution Logic
if ($RemoteComputer) {
    Write-Host "[+] Connecting to remote computer '$RemoteComputer'..." -ForegroundColor Yellow
    $ResultData = Invoke-Command -ComputerName $RemoteComputer -ScriptBlock ${function:Invoke-WorkstationInventory}
} else {
    $ResultData = Invoke-WorkstationInventory
}

# Export Data if Requested
if ($ExportJsonPath -and $ResultData) {
    try {
        $ResultData | ConvertTo-Json -Depth 3 | Out-File -FilePath $ExportJsonPath -Encoding utf8 -ErrorAction Stop
        Write-Host "`n[+] Inventory report exported successfully to: $ExportJsonPath" -ForegroundColor Green
    } catch {
        Write-Host "`n[-] Failed to export JSON report: $_" -ForegroundColor Red
    }
}

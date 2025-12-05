#!powershell

# Copyright: (c) 2024, Ansible Community (@ansible-community)
# GNU General Public License v3.0+ (see COPYING or https://www.gnu.org/licenses/gpl-3.0.txt)

#AnsibleRequires -CSharpUtil Ansible.Basic
#AnsibleRequires -PowerShell ..module_utils._CMPsSetupUtils

$spec = @{
    options = @{
        computer_name = @{ type = 'str'; required = $true }
    }
    supports_check_mode = $true
}

$module = [Ansible.Basic.AnsibleModule]::Create($args, $spec)

# ---- Parameters ----
$serverName = $module.Params.computer_name

$module.Result.changed = $false

# ---- Import SCCM Module ----
Import-CMPsModule -module $module

# ---- Connect to CMSite ----
$siteDrive = Get-PSDrive -PSProvider CMSite -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $siteDrive) {
    $module.FailJson("No CMSite drives found. SCCM console not installed correctly.")
}

Test-CMSiteNameAndConnect -SiteCode $siteDrive.Name -Module $module

# ---- Helper Functions ----
Function Get-WSUSStatusViaCmdlet {
    param (
        [Parameter(Mandatory = $true)][string]$ServerName,
        [Parameter(Mandatory = $true)][ref]$Result
    )

    try {
        $wsusServer = Get-CMSoftwareUpdateSyncStatus -ErrorAction SilentlyContinue |
            Where-Object { $_.WSUSServerName -like "*$ServerName*" } |
            Select-Object -First 1

        if ($wsusServer) {
            # Handle different possible time fields
            $timeValue = $null
            if ($wsusServer.LastSuccessfulSyncTime) {
                $timeValue = $wsusServer.LastSuccessfulSyncTime
            }
            elseif ($wsusServer.LastSyncTime) {
                $timeValue = $wsusServer.LastSyncTime
            }

            if ($timeValue) {
                try {
                    $syncDateTime = [DateTime]$timeValue
                    $Result.Value.last_sync_time = Format-DateTimeAsStringSafely -dateTimeObject $syncDateTime
                }
                catch {
                    $Result.Value.last_sync_time = $timeValue.ToString()
                }
            }

            # Check LastSyncState if available, otherwise use LastSyncResult
            if ($wsusServer.LastSyncState) {
                switch ($wsusServer.LastSyncState) {
                    6704 { $Result.Value.sync_status = "Success" }
                    6703 { $Result.Value.sync_status = "Failed" }
                    6702 { $Result.Value.sync_status = "In Progress" }
                    default { $Result.Value.sync_status = "Unknown" }
                }
            }
            elseif ($wsusServer.LastSyncResult -eq "Success") {
                $Result.Value.sync_status = "Success"
            }
            else {
                $Result.Value.sync_status = "Failed"
            }
            return $true
        }
        return $false
    }
    catch {
        # Method 1 failed, continue to next method
        return $false
    }
}

Function Get-WSUSStatusViaSMSSUPSyncStatus {
    param (
        [Parameter(Mandatory = $true)][string]$ServerName,
        [Parameter(Mandatory = $true)][string]$SiteCode,
        [Parameter(Mandatory = $true)][ref]$Result
    )

    try {
        $syncStatus = Get-CimInstance -ComputerName $ServerName -Namespace "root\sms\site_$SiteCode" `
            -ClassName "SMS_SUPSyncStatus" -ErrorAction SilentlyContinue

        if ($syncStatus) {
            $latestSync = $syncStatus | Sort-Object LastSyncStateTime -Descending | Select-Object -First 1

            # Check for LastSuccessfulSyncTime first, then LastSyncStateTime
            $syncTimeField = $null
            if ($latestSync.LastSuccessfulSyncTime) {
                $syncTimeField = $latestSync.LastSuccessfulSyncTime
            }
            elseif ($latestSync.LastSyncStateTime) {
                $syncTimeField = $latestSync.LastSyncStateTime
            }

            if ($syncTimeField) {
                # Try WMI datetime conversion first, fall back to direct conversion
                try {
                    $syncDateTime = [Management.ManagementDateTimeConverter]::ToDateTime($syncTimeField)
                    $Result.Value.last_sync_time = Format-DateTimeAsStringSafely -dateTimeObject $syncDateTime
                }
                catch {
                    # If WMI conversion fails, try direct datetime conversion
                    try {
                        $syncDateTime = [DateTime]$syncTimeField
                        $Result.Value.last_sync_time = Format-DateTimeAsStringSafely -dateTimeObject $syncDateTime
                    }
                    catch {
                        # If all conversions fail, use string representation
                        $Result.Value.last_sync_time = $syncTimeField.ToString()
                    }
                }
            }

            switch ($latestSync.LastSyncState) {
                6704 { $Result.Value.sync_status = "Success" }
                6703 { $Result.Value.sync_status = "Failed" }
                6702 { $Result.Value.sync_status = "In Progress" }
                default { $Result.Value.sync_status = "Unknown" }
            }
            return $true
        }
        return $false
    }
    catch {
        # Method 2 failed, continue to next method
        return $false
    }
}

Function Get-WSUSStatusViaSMSWSUSServerLocation {
    param (
        [Parameter(Mandatory = $true)][string]$ServerName,
        [Parameter(Mandatory = $true)][string]$SiteCode,
        [Parameter(Mandatory = $true)][ref]$Result
    )

    try {
        $wsusStatus = Get-CimInstance -ComputerName $ServerName -Namespace "root\sms\site_$SiteCode" `
            -ClassName "SMS_WSUSServerLocations" -ErrorAction SilentlyContinue

        if ($wsusStatus) {
            # Get the most recent sync information
            $latestStatus = $wsusStatus | Sort-Object LastSyncTime -Descending | Select-Object -First 1

            if ($latestStatus.LastSyncTime) {
                $syncDateTime = [Management.ManagementDateTimeConverter]::ToDateTime($latestStatus.LastSyncTime)
                $Result.Value.last_sync_time = Format-DateTimeAsStringSafely -dateTimeObject $syncDateTime
            }

            # Determine sync status based on last sync result
            if ($latestStatus.LastSyncResult -eq 0) {
                $Result.Value.sync_status = "Success"
            }
            else {
                $Result.Value.sync_status = "Failed"
            }
            return $true
        }
        return $false
    }
    catch {
        # Method 3 failed, final fallback
        return $false
    }
}

# ---- Get WSUS Sync Status ----
$result = @{
    last_sync_time = $null
    sync_status = "Unknown"
    error_logs = @()
}

# Get the software update point for the specified server
$sup = Get-CMSoftwareUpdatePoint -SiteSystemServerName $serverName -ErrorAction SilentlyContinue

if (-not $sup) {
    $module.FailJson("Software Update Point not found on server: $serverName")
}

# Try multiple methods to get WSUS sync status
$syncDataFound = $false

# Method 1: PowerShell cmdlet (primary method)
if (-not $syncDataFound) {
    $syncDataFound = Get-WSUSStatusViaCmdlet -ServerName $serverName -Result ([ref]$result)
}

# Method 2: SMS_SUPSyncStatus
if (-not $syncDataFound) {
    $syncDataFound = Get-WSUSStatusViaSMSSUPSyncStatus -ServerName $serverName -SiteCode $siteDrive.Name -Result ([ref]$result)
}

# Method 3: SMS_WSUSServerLocations (fallback)
if (-not $syncDataFound) {
    $syncDataFound = Get-WSUSStatusViaSMSWSUSServerLocation -ServerName $serverName -SiteCode $siteDrive.Name -Result ([ref]$result)
}

# If no method worked, add error message
if (-not $syncDataFound) {
    $result.error_logs += "Unable to retrieve WSUS sync status: All methods failed"
}

# Get error logs from SCCM logs if sync failed
if ($result.sync_status -eq "Failed") {
    try {
        # Check for common WSUS sync errors in logs
        $logPath = "\\$serverName\SMS_$($siteDrive.Name)\Logs\wsyncmgr.log"
        if (Test-Path -LiteralPath $logPath) {
            $logContent = Get-Content -LiteralPath $logPath -Tail 20 -ErrorAction SilentlyContinue |
                Where-Object { $_ -match "error|fail|exception" -and $_ -notmatch "Successfully" }

            if ($logContent) {
                $result.error_logs = $logContent | Select-Object -First 5
            }
        }
        else {
            $result.error_logs += "Log file not accessible: $logPath"
        }
    }
    catch {
        $result.error_logs += "Error reading log files: $($_.Exception.Message)"
    }
}

# Set final result
$module.Result.last_sync_time = $result.last_sync_time
$module.Result.sync_status = $result.sync_status
$module.Result.error_logs = $result.error_logs
$module.Result.server_name = $serverName

$module.ExitJson()
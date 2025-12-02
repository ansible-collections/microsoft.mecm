#!powershell

# Copyright: (c) 2024, Ansible Community (@ansible-community)
# GNU General Public License v3.0+ (see COPYING or https://www.gnu.org/licenses/gpl-3.0.txt)

#AnsibleRequires -CSharpUtil Ansible.Basic
#AnsibleRequires -PowerShell ..module_utils._CMPsSetupUtils

$spec = @{
    options = @{
        server_name = @{ type = 'str'; required = $true }
    }
    supports_check_mode = $true
}

$module = [Ansible.Basic.AnsibleModule]::Create($args, $spec)

# ---- Parameters ----
$serverName = $module.Params.server_name

$module.Result.changed = $false

# ---- Import SCCM Module ----
Import-CMPsModule -module $module

# ---- Connect to CMSite ----
$siteDrive = Get-PSDrive -PSProvider CMSite -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $siteDrive) {
    $module.FailJson("No CMSite drives found. SCCM console not installed correctly.")
}

try {
    Set-Location -LiteralPath "$($siteDrive.Name):" -ErrorAction Stop
}
catch {
    $module.FailJson("Unable to enter CMSite drive $($siteDrive.Name): $($_.Exception.Message)")
}

try {
    Get-CMSite -ErrorAction Stop | Out-Null
}
catch {
    $module.FailJson("Get-CMSite failed: $($_.Exception.Message)")
}

# ---- Get WSUS Sync Status ----
$result = @{
    last_sync_time = $null
    sync_status = "Unknown"
    error_logs = @()
}

try {
    # Get the software update point for the specified server
    $sup = Get-CMSoftwareUpdatePoint -SiteSystemServerName $serverName -ErrorAction SilentlyContinue

    if (-not $sup) {
        $module.FailJson("Software Update Point not found on server: $serverName")
    }

    # Try multiple methods to get WSUS sync status
    $syncDataFound = $false

    # Method 1: SMS_WSUSServerLocations
    if (-not $syncDataFound) {
        try {
            $wsusStatus = Get-CimInstance -ComputerName $serverName -Namespace "root\sms\site_$($siteDrive.Name)" `
                -ClassName "SMS_WSUSServerLocations" -ErrorAction SilentlyContinue

            if ($wsusStatus) {
                # Get the most recent sync information
                $latestStatus = $wsusStatus | Sort-Object LastSyncTime -Descending | Select-Object -First 1

                if ($latestStatus.LastSyncTime) {
                    $syncDateTime = [Management.ManagementDateTimeConverter]::ToDateTime($latestStatus.LastSyncTime)
                    $result.last_sync_time = $syncDateTime.ToString("yyyy-MM-dd HH:mm:ss")
                }

                # Determine sync status based on last sync result
                if ($latestStatus.LastSyncResult -eq 0) {
                    $result.sync_status = "Success"
                }
                else {
                    $result.sync_status = "Failed"
                }
                $syncDataFound = $true
            }
        }
        catch {
            # Method 1 failed, continue to next method
            Write-Verbose "Method 1 (SMS_WSUSServerLocations) failed: $($_.Exception.Message)"
        }
    }

    # Method 2: SMS_SUPSyncStatus
    if (-not $syncDataFound) {
        try {
            $syncStatus = Get-CimInstance -ComputerName $serverName -Namespace "root\sms\site_$($siteDrive.Name)" `
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
                        $result.last_sync_time = $syncDateTime.ToString("yyyy-MM-dd HH:mm:ss")
                    }
                    catch {
                        # If WMI conversion fails, try direct datetime conversion
                        try {
                            $syncDateTime = [DateTime]$syncTimeField
                            $result.last_sync_time = $syncDateTime.ToString("yyyy-MM-dd HH:mm:ss")
                        }
                        catch {
                            # If all conversions fail, use string representation
                            $result.last_sync_time = $syncTimeField.ToString()
                        }
                    }
                }

                switch ($latestSync.LastSyncState) {
                    6704 {
                        $result.sync_status = "Success"
                    }
                    6703 {
                        $result.sync_status = "Failed"
                    }
                    6702 {
                        $result.sync_status = "In Progress"
                    }
                    default {
                        $result.sync_status = "Unknown"
                    }
                }
                $syncDataFound = $true
            }
        }
        catch {
            # Method 2 failed, continue to next method
            Write-Verbose "Method 2 (SMS_SUPSyncStatus) failed: $($_.Exception.Message)"
        }
    }

    # Method 3: PowerShell cmdlet fallback
    if (-not $syncDataFound) {
        try {
            $wsusServer = Get-CMSoftwareUpdateSyncStatus -ErrorAction SilentlyContinue |
                Where-Object { $_.WSUSServerName -like "*$serverName*" } |
                Select-Object -First 1

            if ($wsusServer) {
                # Handle different possible time fields from Method 3
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
                        $result.last_sync_time = $syncDateTime.ToString("yyyy-MM-dd HH:mm:ss")
                    }
                    catch {
                        $result.last_sync_time = $timeValue.ToString()
                    }
                }

                # Check LastSyncState if available, otherwise use LastSyncResult
                if ($wsusServer.LastSyncState) {
                    switch ($wsusServer.LastSyncState) {
                        6704 { $result.sync_status = "Success" }
                        6703 { $result.sync_status = "Failed" }
                        6702 { $result.sync_status = "In Progress" }
                        default { $result.sync_status = "Unknown" }
                    }
                }
                elseif ($wsusServer.LastSyncResult -eq "Success") {
                    $result.sync_status = "Success"
                }
                else {
                    $result.sync_status = "Failed"
                }
            }
            $syncDataFound = $true
        }
        catch {
            $result.error_logs += "Unable to retrieve WSUS sync status: $($_.Exception.Message)"
        }
    }

    # Get error logs from SCCM logs if sync failed
    if ($result.sync_status -eq "Failed") {
        try {
            # Check for common WSUS sync errors in logs
            $logPath = "\\$serverName\SMS_$($siteDrive.Name)\Logs\wsyncmgr.log"
            if (Test-Path -LiteralPath $logPath) {
                $logContent = Get-Content -LiteralPath $logPath -Tail 20 -ErrorAction SilentlyContinue | `
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

}
catch {
    $module.FailJson("Failed to retrieve WSUS sync status: $($_.Exception.Message)")
}

$module.ExitJson()
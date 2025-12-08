#!powershell

# Copyright: (c) 2024, Ansible Community (@ansible-community)
# GNU General Public License v3.0+ (see COPYING or https://www.gnu.org/licenses/gpl-3.0.txt)

#AnsibleRequires -CSharpUtil Ansible.Basic
#AnsibleRequires -PowerShell ..module_utils._CMPsSetupUtils

$spec = @{
    options = @{
        computer_name = @{ required = $false; type = "str" }
        backup_task_name = @{ required = $false; type = "str"; default = "Backup SMS Site Server" }
        site_code = @{ required = $true; type = "str" }
    }
    supports_check_mode = $true
}

$module = [Ansible.Basic.AnsibleModule]::Create($args, $spec)

# ---- Parameters ----
# Use Get-LocalComputerFQDN from module utilities for consistent FQDN resolution
$server = if ($module.Params.computer_name) { $module.Params.computer_name } else { Get-LocalComputerFQDN }
$backupTaskName = $module.Params.backup_task_name
$siteCode = $module.Params.site_code

$module.Result.changed = $false


# ---- Import SCCM Module using Module Utilities ----
# Import-CMPsModule ensures ConfigurationManager module is available and imports it
Import-CMPsModule -module $module

# ---- Connect to CMSite using user-specified site name ----
# Test-CMSiteNameAndConnect verifies site name and establishes connection
Test-CMSiteNameAndConnect -SiteCode $siteCode -Module $module


# ---- Query Backup Status ----
try {
    # Use the correct cmdlet that actually exists: Get-CMSiteMaintenanceTask
    $backupTask = Get-CMSiteMaintenanceTask -TaskName $backupTaskName -ErrorAction Stop
}
catch {
    $module.FailJson("Failed to query backup maintenance task: $($_.Exception.Message)")
}

# Initialize result variables
$taskEnabled = $false
$lastBackupStatus = "Unknown"
$lastBackupTime = ""
$backupLocation = ""
$daysOfWeek = 0
$scheduleInfo = ""

if ($backupTask) {
    $taskEnabled = $backupTask.Enabled
    $daysOfWeek = $backupTask.DaysOfWeek

    # Convert DaysOfWeek bitmask to readable format
    $scheduleInfo = if ($daysOfWeek -eq 127) { "Daily" }
    elseif ($daysOfWeek -eq 64) { "Sunday" }
    elseif ($daysOfWeek -eq 1) { "Monday" }
    elseif ($daysOfWeek -eq 2) { "Tuesday" }
    elseif ($daysOfWeek -eq 4) { "Wednesday" }
    elseif ($daysOfWeek -eq 8) { "Thursday" }
    elseif ($daysOfWeek -eq 16) { "Friday" }
    elseif ($daysOfWeek -eq 32) { "Saturday" }
    else { "Custom ($daysOfWeek)" }
    # Get backup device name if configured
    if ($backupTask.DeviceName) {
        $backupLocation = $backupTask.DeviceName
    }
    # Try to get backup execution status from WMI
    try {
        $sqlTaskStatus = Get-CimInstance -Namespace "root\SMS\site_$($site.SiteCode)" `
            -ClassName "SMS_SQLTaskStatus" -Filter "TaskName='Backup SMS Site Server'" -ErrorAction SilentlyContinue
        if ($sqlTaskStatus) {
            # Get last completion message ID for status determination
            if ($sqlTaskStatus.LastCompletionMessageID) {
                $lastBackupStatus = switch ($sqlTaskStatus.LastCompletionMessageID) {
                    0 { "Success" }
                    1 { "Failed" }
                    default { "Unknown" }
                }
            }
            # Get last run time if available
            if ($sqlTaskStatus.LastRunTime) {
                $lastBackupTime = [System.Management.ManagementDateTimeConverter]::ToDateTime($sqlTaskStatus.LastRunTime).ToString("yyyy-MM-ddTHH:mm:ssZ")
            }
        }
        # Try to get status messages for backup component
        $statusMessages = Get-CimInstance -Namespace "root\SMS\site_$($site.SiteCode)" `
            -ClassName "SMS_StatusMessage" -Filter "Component='SMS_SITE_BACKUP'" `
            -ErrorAction SilentlyContinue | Sort-Object TimeKey -Descending | Select-Object -First 1
        if ($statusMessages -and -not $lastBackupTime) {
            # Use the most recent status message time if no LastRunTime
            if ($statusMessages.TimeKey) {
                $lastBackupTime = [System.Management.ManagementDateTimeConverter]::ToDateTime($statusMessages.TimeKey).ToString("yyyy-MM-ddTHH:mm:ssZ")
            }
            # Determine status from message severity if not already determined
            if ($lastBackupStatus -eq "Unknown" -and $statusMessages.Severity) {
                $severityString = ConvertTo-SeverityString -SeverityCode $statusMessages.Severity.ToString()
                $lastBackupStatus = switch ($severityString) {
                    "information" { "Success" }
                    "warning" { "Warning" }
                    "error" { "Failed" }
                    default { "Unknown" }
                }
            }
        }
    }
    catch {
        # WMI queries failed, but we still have basic task info
        # Keep default values (Unknown status, no time)
        Write-Verbose "WMI query failed: $($_.Exception.Message)"
    }
}

# ---- Build Results ----
$result = @{
    task_enabled = $taskEnabled
    last_backup_status = $lastBackupStatus
    last_backup_time = $lastBackupTime
    backup_location = $backupLocation
    schedule_info = $scheduleInfo
    days_of_week_bitmask = $daysOfWeek
    computer_name = $server
    site_code = $site.SiteCode
    task_type = if ($backupTask) { $backupTask.TaskType } else { $null }
}

# Set appropriate status based on configuration
if (-not $taskEnabled) {
    $result.last_backup_status = "Task Disabled"
}
elseif ($lastBackupStatus -eq "Unknown" -and -not $lastBackupTime) {
    $result.last_backup_status = "No Backup History"
}

$module.Result.backup_status = $result
$module.ExitJson()
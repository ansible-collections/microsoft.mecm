#!powershell

# Copyright: (c) 2025, Ansible Project
# GNU General Public License v3.0+ (see COPYING or https://www.gnu.org/licenses/gpl-3.0.txt)

#AnsibleRequires -CSharpUtil Ansible.Basic
#AnsibleRequires -PowerShell ..module_utils._CMPsSetupUtils
#AnsibleRequires -PowerShell ..module_utils._MaintenanceWindowUtils


$spec = @{
    options = @{
        site_code = @{ type = 'str'; required = $true }
        device_collection_name = @{ type = 'str'; required = $true }
        name = @{ type = 'str'; required = $true }
        state = @{
            type = 'str'
            required = $false
            default = 'present'
            choices = @('present', 'absent')
        }
        apply_to = @{
            type = 'str'
            required = $false
            default = 'Any'
            choices = @('Any', 'SoftwareUpdatesOnly', 'TaskSequencesOnly')
        }
        sched_recur_type = @{
            type = 'str'
            required = $false
            default = 'None'
            choices = @('None', 'Daily')
        }
        sched_duration_count = @{ type = 'int'; required = $false }
        sched_duration_interval = @{
            type = 'str'
            required = $false
            choices = @('Minutes', 'Hours', 'Days')
        }
        sched_recur_count = @{ type = 'int'; required = $false }
        sched_start = @{ type = 'str'; required = $false }
    }
    supports_check_mode = $true
}

$module = [Ansible.Basic.AnsibleModule]::Create($args, $spec)
$module.result.changed = $false
$module.result.maintenance_window = @{}

$site_code = $module.Params.site_code
$device_collection_name = $module.Params.device_collection_name
$name = $module.Params.name
$state = $module.Params.state
$apply_to = $module.Params.apply_to
$sched_recur_type = $module.Params.sched_recur_type
$sched_duration_count = $module.Params.sched_duration_count
$sched_duration_interval = $module.Params.sched_duration_interval
$sched_recur_count = $module.Params.sched_recur_count
$sched_start = $module.Params.sched_start

# Validate that all required schedule parameters are provided when state=present.
if ($state -eq 'present') {
    foreach ($param_name in @('sched_duration_count', 'sched_duration_interval', 'sched_start')) {
        if ($null -eq $module.Params.$param_name) {
            $module.FailJson("Parameter '$param_name' is required when state=present.")
        }
    }
    if ($sched_recur_type -eq 'Daily' -and $null -eq $sched_recur_count) {
        $module.FailJson("Parameter 'sched_recur_count' is required when sched_recur_type=Daily.")
    }
    if ($sched_recur_type -eq 'Daily' -and ($sched_recur_count -lt 1 -or $sched_recur_count -gt 31)) {
        $module.FailJson("Parameter 'sched_recur_count' must be between 1 and 31 for Daily recurrence.")
    }
}

Import-CMPsModule -module $module
Test-CMSiteNameAndConnect -module $module -SiteCode $site_code

# Verify the device collection exists before proceeding.
$collection = Get-CMCollection -Name $device_collection_name -ErrorAction SilentlyContinue
if ($null -eq $collection) {
    $module.FailJson("Device collection '$device_collection_name' does not exist.")
}
$collection_id = $collection.CollectionID

$existing_mw = Get-CMMaintenanceWindow -CollectionID $collection_id -MaintenanceWindowName $name -DisableWildcardHandling -ErrorAction SilentlyContinue

if ($state -eq 'absent') {
    if ($null -ne $existing_mw) {
        $module.result.changed = $true
        $module.result.maintenance_window = Format-MaintenanceWindowResult -mw $existing_mw
        if (-not $module.CheckMode) {
            try {
                Remove-CMMaintenanceWindow -CollectionID $collection_id -Name $name -Force -Confirm:$false
            }
            catch {
                $module.FailJson("Failed to remove maintenance window '$name': $($_.Exception.Message)", $_)
            }
        }
    }
}
elseif ($state -eq 'present') {
    try {
        $start_datetime = [datetime]::Parse($sched_start)
        if ($sched_recur_type -eq 'Daily') {
            $mw_schedule = New-CMSchedule `
                -Start $start_datetime `
                -DurationCount $sched_duration_count `
                -DurationInterval $sched_duration_interval `
                -RecurCount $sched_recur_count `
                -RecurInterval Days `
                -ErrorAction Stop
        }
        else {
            $mw_schedule = New-CMSchedule `
                -Start $start_datetime `
                -DurationCount $sched_duration_count `
                -DurationInterval $sched_duration_interval `
                -Nonrecurring `
                -ErrorAction Stop
        }
    }
    catch {
        $module.FailJson("Failed to build maintenance window schedule: $($_.Exception.Message)", $_)
    }

    if ($null -eq $existing_mw) {
        # Create the maintenance window.
        try {
            New-CMMaintenanceWindow `
                -CollectionId $collection_id `
                -Name $name `
                -Schedule $mw_schedule `
                -ApplyTo $apply_to `
                -WhatIf:$module.CheckMode `
                -ErrorAction Stop | Out-Null
        }
        catch {
            $module.FailJson("Failed to create maintenance window '$name': $($_.Exception.Message)", $_)
        }
        $module.result.changed = $true

        if (-not $module.CheckMode) {
            $created_mw = Get-CMMaintenanceWindow -CollectionID $collection_id -MaintenanceWindowName $name `
                -DisableWildcardHandling -ErrorAction SilentlyContinue
            if ($null -ne $created_mw) {
                $module.result.maintenance_window = Format-MaintenanceWindowResult -mw $created_mw
            }
        }
        else {
            $module.result.maintenance_window = @{
                name = $name
                apply_to = $apply_to
                is_enabled = $true
            }
        }
    }
    else {
        $needs_update = $false
        $existing_type_int = [int]$existing_mw.ServiceWindowType
        $desired_type_int = ConvertTo-ServiceWindowTypeInt -ApplyTo $apply_to
        if ($existing_type_int -ne $desired_type_int) {
            $needs_update = $true
        }

        if (-not $needs_update) {
            try {
                $desired_schedule_hex = Convert-CMSchedule -InputObject $mw_schedule -ErrorAction Stop
                if ([string]$desired_schedule_hex -ne $existing_mw.ServiceWindowSchedules) {
                    $needs_update = $true
                }
            }
            catch {
                $module.FailJson("Failed to convert desired schedule to hex token: $($_.Exception.Message)", $_)
            }
        }

        if ($needs_update) {
            try {
                Set-CMMaintenanceWindow `
                    -Name $name `
                    -CollectionID $collection_id `
                    -ApplyTo $apply_to `
                    -Schedule $mw_schedule `
                    -WhatIf:$module.CheckMode `
                    -ErrorAction Stop | Out-Null
            }
            catch {
                $module.FailJson("Failed to update maintenance window '$name': $($_.Exception.Message)", $_)
            }
            $module.result.changed = $true
        }

        if (-not $module.CheckMode) {
            $final_mw = Get-CMMaintenanceWindow -CollectionID $collection_id -MaintenanceWindowName $name -DisableWildcardHandling -ErrorAction SilentlyContinue
            if ($null -ne $final_mw) {
                $module.result.maintenance_window = Format-MaintenanceWindowResult -mw $final_mw
            }
        }
        else {
            $module.result.maintenance_window = Format-MaintenanceWindowResult -mw $existing_mw
        }
    }
}

$module.ExitJson()

#!powershell

# Copyright: (c) 2026, Ansible Project
# GNU General Public License v3.0+ (see COPYING or https://www.gnu.org/licenses/gpl-3.0.txt)

#AnsibleRequires -CSharpUtil Ansible.Basic
#AnsibleRequires -PowerShell ..module_utils._CMPsSetupUtils


function ConvertFrom-CMRefreshType {
    param ([int]$value)
    switch ($value) {
        1 { return 'Manual' }
        2 { return 'Periodic' }
        4 { return 'Continuous' }
        6 { return 'Both' }
        default { return "Unknown ($value)" }
    }
}


function Format-DeviceCollectionResult {
    param ([Parameter(Mandatory = $true)][object]$collection)
    return @{
        name = $collection.Name
        collection_id = $collection.CollectionID
        limiting_collection_name = $collection.LimitToCollectionName
        refresh_type = ConvertFrom-CMRefreshType -value ([int]$collection.RefreshType)
        member_count = $collection.MemberCount
        comment = $collection.Comment
        is_built_in = [bool]$collection.IsBuiltIn
    }
}


function Assert-ScheduleParams {
    param (
        [Parameter(Mandatory = $true)][string]$recurInterval,
        [Parameter(Mandatory = $true)][int]$recurCount
    )
    switch ($recurInterval) {
        'Days' {
            if ($recurCount -lt 1 -or $recurCount -gt 31) {
                return "schedule_recur_count must be between 1 and 31 when schedule_recur_interval is 'Days' (got $recurCount)."
            }
        }
        'Hours' {
            if ($recurCount -lt 1 -or $recurCount -gt 23) {
                return "schedule_recur_count must be between 1 and 23 when schedule_recur_interval is 'Hours' (got $recurCount)."
            }
        }
        'Minutes' {
            if ($recurCount -lt 1 -or $recurCount -gt 59) {
                return "schedule_recur_count must be between 1 and 59 when schedule_recur_interval is 'Minutes' (got $recurCount)."
            }
        }
    }
    return $null
}


function New-DeviceCollectionSchedule {
    param (
        [Parameter(Mandatory = $true)][string]$recurInterval,
        [Parameter(Mandatory = $true)][int]$recurCount,
        [Parameter(Mandatory = $true)][datetime]$start
    )
    return New-CMSchedule `
        -DurationInterval $recurInterval `
        -DurationCount $recurCount `
        -RecurInterval $recurInterval `
        -RecurCount $recurCount `
        -Start $start
}


$spec = @{
    options = @{
        site_code = @{ type = 'str'; required = $true }
        name = @{ type = 'str'; required = $true }
        limiting_collection_name = @{ type = 'str'; required = $false }
        refresh_type = @{ type = 'str'; required = $false; choices = @('Manual', 'Periodic', 'Continuous', 'Both') }
        schedule_recur_interval = @{ type = 'str'; required = $false; choices = @('Minutes', 'Hours', 'Days') }
        schedule_recur_count = @{ type = 'int'; required = $false }
        schedule_start = @{ type = 'str'; required = $false }
        state = @{ type = 'str'; required = $false; default = 'present'; choices = @('present', 'absent') }
    }
    supports_check_mode = $true
}

$module = [Ansible.Basic.AnsibleModule]::Create($args, $spec)
$module.result.changed = $false
$module.result.device_collection = @{}

$site_code = $module.Params.site_code
$name = $module.Params.name
$limiting_collection_name = $module.Params.limiting_collection_name
$refresh_type = $module.Params.refresh_type
$schedule_recur_interval = $module.Params.schedule_recur_interval
$schedule_recur_count = $module.Params.schedule_recur_count
$schedule_start = $module.Params.schedule_start
$state = $module.Params.state

# Validate schedule parameters: all three must be provided together or not at all
$schedule_params_provided = @($schedule_recur_interval, $schedule_recur_count, $schedule_start) | Where-Object { $null -ne $_ }
if ($schedule_params_provided.Count -gt 0 -and $schedule_params_provided.Count -lt 3) {
    $module.FailJson("All three schedule parameters must be provided together: schedule_recur_interval, schedule_recur_count, schedule_start.")
}
$has_schedule = ($schedule_params_provided.Count -eq 3)

# Schedule parameters are only valid when refresh_type is Periodic or Both
if ($has_schedule -and ($refresh_type -ne 'Periodic' -and $refresh_type -ne 'Both')) {
    $module.FailJson(
        "Schedule parameters (schedule_recur_interval, schedule_recur_count, schedule_start) " +
        "are only allowed when refresh_type is 'Periodic' or 'Both'."
    )
}

# Parse schedule_start string to DateTime and validate recur count range
$schedule_start_dt = $null
if ($has_schedule) {
    try {
        $schedule_start_dt = [datetime]::Parse($schedule_start)
    }
    catch {
        $module.FailJson("Invalid schedule_start value '$schedule_start'. Expected a valid date/time string, e.g. '2026-06-09 08:00'.")
    }

    $schedule_err = Assert-ScheduleParams -recurInterval $schedule_recur_interval -recurCount $schedule_recur_count
    if ($null -ne $schedule_err) {
        $module.FailJson($schedule_err)
    }
}

Import-CMPsModule -module $module
Test-CMSiteNameAndConnect -module $module -SiteCode $site_code

$existing_dc = Get-CMDeviceCollection -Name $name -ErrorAction SilentlyContinue

if ($state -eq 'absent') {
    if ($null -ne $existing_dc) {
        $module.result.changed = $true
        $module.result.device_collection = Format-DeviceCollectionResult -collection $existing_dc
        if (-not $module.CheckMode) {
            try {
                Remove-CMDeviceCollection -Name $name -Force -Confirm:$false
            }
            catch {
                $module.FailJson("Failed to remove device collection '$name': $($_.Exception.Message)", $_)
            }
        }
    }
}
elseif ($state -eq 'present') {
    if ($null -eq $existing_dc) {
        if ([string]::IsNullOrEmpty($limiting_collection_name)) {
            $module.FailJson("'limiting_collection_name' is required when creating a new device collection.")
        }

        $module.result.changed = $true

        $create_params = @{
            Name = $name
            LimitingCollectionName = $limiting_collection_name
        }

        if (-not [string]::IsNullOrEmpty($refresh_type)) {
            $create_params.RefreshType = $refresh_type
        }

        if ($has_schedule -and ($refresh_type -eq 'Periodic' -or $refresh_type -eq 'Both')) {
            try {
                $create_params.RefreshSchedule = New-DeviceCollectionSchedule `
                    -recurInterval $schedule_recur_interval `
                    -recurCount $schedule_recur_count `
                    -start $schedule_start_dt
            }
            catch {
                $module.FailJson("Failed to create refresh schedule: $($_.Exception.Message)", $_)
            }
        }

        try {
            $null = New-CMDeviceCollection @create_params -WhatIf:$module.CheckMode
        }
        catch {
            $module.FailJson("Failed to create device collection '$name': $($_.Exception.Message)", $_)
        }

        if (-not $module.CheckMode) {
            $new_dc = Get-CMDeviceCollection -Name $name -ErrorAction SilentlyContinue
            $module.result.device_collection = Format-DeviceCollectionResult -collection $new_dc
        }
        else {
            $module.result.device_collection = @{
                name = $name
                collection_id = 'check_mode'
                limiting_collection_name = $limiting_collection_name
                refresh_type = if (-not [string]::IsNullOrEmpty($refresh_type)) { $refresh_type } else { 'Manual' }
                member_count = 0
                comment = ''
                is_built_in = $false
            }
        }
    }
    else {
        $needs_update = $false
        $refresh_type_changed = $false
        $limiting_collection_changed = $false
        $schedule_changed = $false

        # Always resolve current refresh type string so it is available for schedule comparison
        $current_rt_str = ConvertFrom-CMRefreshType -value ([int]$existing_dc.RefreshType)

        if (-not [string]::IsNullOrEmpty($limiting_collection_name) -and
            $limiting_collection_name -ne $existing_dc.LimitToCollectionName) {
            $needs_update = $true
            $limiting_collection_changed = $true
        }

        if (-not [string]::IsNullOrEmpty($refresh_type) -and $refresh_type -ne $current_rt_str) {
            $needs_update = $true
            $refresh_type_changed = $true
        }

        # Effective refresh type after any pending change
        $effective_rt = if (-not [string]::IsNullOrEmpty($refresh_type)) { $refresh_type } else { $current_rt_str }

        # Compare schedule parameters when the user supplied them and the effective type supports a schedule
        if ($has_schedule -and ($effective_rt -eq 'Periodic' -or $effective_rt -eq 'Both')) {
            $sched = @($existing_dc.RefreshSchedule)[0]

            if ($null -eq $sched) {
                $schedule_changed = $true
            }
            else {
                # Map existing span properties back to interval unit and count
                $current_interval = $null
                $current_count = 0
                if ([int]$sched.DaySpan -gt 0) {
                    $current_interval = 'Days'
                    $current_count = [int]$sched.DaySpan
                }
                elseif ([int]$sched.HourSpan -gt 0) {
                    $current_interval = 'Hours'
                    $current_count = [int]$sched.HourSpan
                }
                elseif ([int]$sched.MinuteSpan -gt 0) {
                    $current_interval = 'Minutes'
                    $current_count = [int]$sched.MinuteSpan
                }

                if ($current_interval -ne $schedule_recur_interval -or $current_count -ne $schedule_recur_count) {
                    $schedule_changed = $true
                }

                # Compare start time at minute precision
                $current_start_dt = $null
                $start_raw = $sched.StartTime
                if (-not [string]::IsNullOrEmpty($start_raw)) {
                    try {
                        $current_start_dt = [System.Management.ManagementDateTimeConverter]::ToDateTime($start_raw.ToString())
                    }
                    catch {
                        try { $current_start_dt = [datetime]::Parse($start_raw.ToString()) } catch { }
                    }
                }

                if ($null -eq $current_start_dt -or
                    [math]::Abs(($schedule_start_dt - $current_start_dt).TotalMinutes) -gt 1) {
                    $schedule_changed = $true
                }
            }

            if ($schedule_changed) { $needs_update = $true }
        }

        if ($needs_update) {
            $module.result.changed = $true
            $set_params = @{ Name = $name }

            if ($limiting_collection_changed) {
                $set_params.LimitingCollectionName = $limiting_collection_name
            }

            if ($refresh_type_changed) {
                $set_params.RefreshType = $refresh_type
            }

            if (($refresh_type_changed -or $schedule_changed) -and
                $has_schedule -and ($effective_rt -eq 'Periodic' -or $effective_rt -eq 'Both')) {
                try {
                    $set_params.RefreshSchedule = New-DeviceCollectionSchedule `
                        -recurInterval $schedule_recur_interval `
                        -recurCount $schedule_recur_count `
                        -start $schedule_start_dt
                }
                catch {
                    $module.FailJson("Failed to create refresh schedule: $($_.Exception.Message)", $_)
                }
            }

            try {
                $null = Set-CMCollection @set_params -Confirm:$false -WhatIf:$module.CheckMode
            }
            catch {
                $module.FailJson("Failed to update device collection '$name' via Set-CMCollection: $($_.Exception.Message)", $_)
            }
        }

        if (-not $module.CheckMode) {
            $updated_dc = Get-CMDeviceCollection -Name $name -ErrorAction SilentlyContinue
            $module.result.device_collection = Format-DeviceCollectionResult -collection $updated_dc
        }
        else {
            $module.result.device_collection = @{
                name = $name
                collection_id = $existing_dc.CollectionID
                limiting_collection_name = if ($limiting_collection_changed) { $limiting_collection_name } else { $existing_dc.LimitToCollectionName }
                refresh_type = $effective_rt
                member_count = $existing_dc.MemberCount
                comment = $existing_dc.Comment
                is_built_in = [bool]$existing_dc.IsBuiltIn
            }
        }
    }
}

$module.ExitJson()

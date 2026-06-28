#!powershell

# Copyright: (c) 2026, Ansible Project
# GNU General Public License v3.0+ (see COPYING or https://www.gnu.org/licenses/gpl-3.0.txt)

#AnsibleRequires -CSharpUtil Ansible.Basic
#AnsibleRequires -PowerShell ..module_utils._CMPsSetupUtils
#AnsibleRequires -PowerShell ..module_utils._DeviceCollectionUtils


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


function Assert-ScheduleParam {
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


function Get-CollectionQueryRule {
    param (
        [Parameter(Mandatory = $true)][object]$module,
        [Parameter(Mandatory = $true)][string]$collectionName
    )
    try {
        return @(Get-CMDeviceCollectionQueryMembershipRule -CollectionName $collectionName -ErrorAction Stop)
    }
    catch {
        $module.FailJson("Failed to query query membership rules for '$collectionName': $($_.Exception.Message)", $_)
    }
}


function Get-CollectionDirectRule {
    param (
        [Parameter(Mandatory = $true)][object]$module,
        [Parameter(Mandatory = $true)][string]$collectionName
    )
    try {
        return @(Get-CMDeviceCollectionDirectMembershipRule -CollectionName $collectionName -ErrorAction Stop)
    }
    catch {
        $module.FailJson("Failed to query direct membership rules for '$collectionName': $($_.Exception.Message)", $_)
    }
}


function Format-CollectionRulesResult {
    param (
        [Parameter(Mandatory = $true)][object]$module,
        [Parameter(Mandatory = $true)][string]$collectionName
    )
    $queryRulesRaw = Get-CollectionQueryRule -module $module -collectionName $collectionName
    $directRulesRaw = Get-CollectionDirectRule -module $module -collectionName $collectionName
    return @{
        device_collection_query_rules = @($queryRulesRaw | ForEach-Object { @{ rule_name = $_.RuleName; query_expression = $_.QueryExpression } })
        device_collection_direct_rules = @($directRulesRaw | ForEach-Object { @{ resource_id = [int]$_.ResourceID; rule_name = $_.RuleName } })
    }
}


function Get-QueryFilter {
    # MECM rewrites the SELECT column list when storing a query rule (it always
    # expands it to the full set of standard device fields), but preserves the
    # FROM / JOIN / WHERE conditions that actually define membership.
    # Strip the SELECT portion and normalise the remainder so idempotency
    # comparisons are not defeated by MECM's column-list rewriting.
    param ([string]$expr)
    $normalized = [regex]::Replace($expr.Trim().ToUpper(), '\s+', ' ')
    $fromIdx = $normalized.IndexOf(' FROM ')
    if ($fromIdx -ge 0) { return $normalized.Substring($fromIdx).Trim() }
    return $normalized
}


function Sync-CollectionRule {
    param (
        [Parameter(Mandatory = $true)][object]$module,
        [Parameter(Mandatory = $true)][string]$collectionName,
        [AllowNull()][AllowEmptyCollection()][object[]]$desiredQueryRules,
        [AllowNull()][AllowEmptyCollection()][object[]]$desiredDirectRules,
        [bool]$collectionExists = $true
    )

    $manageQuery = ($null -ne $desiredQueryRules)
    $manageDirect = ($null -ne $desiredDirectRules)

    $currentQueryRules = @()
    $currentDirectRules = @()
    if ($collectionExists) {
        if ($manageQuery) { $currentQueryRules = Get-CollectionQueryRule -module $module -collectionName $collectionName }
        if ($manageDirect) { $currentDirectRules = Get-CollectionDirectRule -module $module -collectionName $collectionName }
    }

    # Query rules
    if ($manageQuery) {
        $currentQueryRuleNames = @($currentQueryRules | ForEach-Object { $_.RuleName })
        $desiredQueryRuleNames = @($desiredQueryRules | ForEach-Object { $_.rule_name })

        $queryToRemove = @($currentQueryRuleNames | Where-Object { $_ -notin $desiredQueryRuleNames })
        $queryToAdd = @($desiredQueryRules | Where-Object { $_.rule_name -notin $currentQueryRuleNames })
        $queryToUpdate = @(
            foreach ($desiredRule in $desiredQueryRules) {
                $cur = $currentQueryRules | Where-Object { $_.RuleName -eq $desiredRule.rule_name } | Select-Object -First 1
                $exprChanged = ($null -ne $cur) -and ((Get-QueryFilter $cur.QueryExpression) -ne (Get-QueryFilter $desiredRule.query_expression))
                if ($exprChanged) { $desiredRule }
            }
        )

        foreach ($ruleName in $queryToRemove) {
            $module.result.changed = $true
            if (-not $module.CheckMode) {
                try {
                    Remove-CMDeviceCollectionQueryMembershipRule -CollectionName $collectionName `
                        -RuleName $ruleName -Force -Confirm:$false -ErrorAction Stop
                }
                catch {
                    $module.FailJson("Failed to remove query rule '$ruleName' from '$collectionName': $($_.Exception.Message)", $_)
                }
            }
        }

        foreach ($rule in $queryToUpdate) {
            $module.result.changed = $true
            if (-not $module.CheckMode) {
                try {
                    Remove-CMDeviceCollectionQueryMembershipRule -CollectionName $collectionName `
                        -RuleName $rule.rule_name -Force -Confirm:$false -ErrorAction Stop
                }
                catch {
                    $module.FailJson("Failed to remove query rule '$($rule.rule_name)' before update in '$collectionName': $($_.Exception.Message)", $_)
                }
                try {
                    Add-CMDeviceCollectionQueryMembershipRule -CollectionName $collectionName `
                        -RuleName $rule.rule_name -QueryExpression $rule.query_expression -ErrorAction Stop
                }
                catch {
                    $module.FailJson("Failed to re-add updated query rule '$($rule.rule_name)' to '$collectionName': $($_.Exception.Message)", $_)
                }
            }
        }

        foreach ($rule in $queryToAdd) {
            $module.result.changed = $true
            if (-not $module.CheckMode) {
                try {
                    Add-CMDeviceCollectionQueryMembershipRule -CollectionName $collectionName `
                        -RuleName $rule.rule_name -QueryExpression $rule.query_expression -ErrorAction Stop
                }
                catch {
                    $module.FailJson("Failed to add query rule '$($rule.rule_name)' to '$collectionName': $($_.Exception.Message)", $_)
                }
            }
        }
    }

    # Direct rules
    if ($manageDirect) {
        $desiredResourceIds = @($desiredDirectRules | ForEach-Object { $_.resource_id } | Sort-Object -Unique)
        $currentResourceIds = @($currentDirectRules | ForEach-Object { [int]$_.ResourceID })

        $directToAdd = @($desiredResourceIds | Where-Object { $_ -notin $currentResourceIds })
        $directToRemove = @($currentResourceIds | Where-Object { $_ -notin $desiredResourceIds })

        # Validate every resource ID about to be added before making any changes.
        # Add-CMDeviceCollectionDirectMembershipRule only emits a non-terminating warning for
        # invalid/wrong-type resources, so the problem must be caught here.
        foreach ($resourceId in $directToAdd) {
            $device = $null
            try {
                $device = Get-CMDevice -ResourceId $resourceId -ErrorAction Stop
            }
            catch {
                $module.FailJson(
                    "Failed to validate resource ID $resourceId for direct rule: $($_.Exception.Message)", $_)
            }
            if ($null -eq $device) {
                $module.FailJson(
                    "Resource ID $resourceId is not a valid device resource. " +
                    "Verify it exists in MECM and is of type SMS_R_System (computer/workstation/server).")
            }
        }

        foreach ($resourceId in $directToRemove) {
            $module.result.changed = $true
            if (-not $module.CheckMode) {
                try {
                    Remove-CMDeviceCollectionDirectMembershipRule -CollectionName $collectionName `
                        -ResourceId $resourceId -Force -Confirm:$false -ErrorAction Stop
                }
                catch {
                    $module.FailJson("Failed to remove direct rule for resource $resourceId from '$collectionName': $($_.Exception.Message)", $_)
                }
            }
        }

        foreach ($resourceId in $directToAdd) {
            $module.result.changed = $true
            if (-not $module.CheckMode) {
                try {
                    Add-CMDeviceCollectionDirectMembershipRule -CollectionName $collectionName `
                        -ResourceId $resourceId -ErrorAction Stop
                }
                catch {
                    $module.FailJson("Failed to add direct rule for resource $resourceId to '$collectionName': $($_.Exception.Message)", $_)
                }
            }
        }
    }
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
        device_collection_query_rules = @{
            type = 'list'
            elements = 'dict'
            required = $false
            options = @{
                rule_name = @{ type = 'str'; required = $true }
                query_expression = @{ type = 'str'; required = $true }
            }
        }
        device_collection_direct_rules = @{
            type = 'list'
            elements = 'dict'
            required = $false
            options = @{
                resource_id = @{ type = 'int'; required = $true }
            }
        }
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
$dc_query_rules = $module.Params.device_collection_query_rules
$dc_direct_rules = $module.Params.device_collection_direct_rules
$state = $module.Params.state

Import-CMPsModule -module $module
Test-CMSiteNameAndConnect -module $module -SiteCode $site_code

try {
    $existing_dc = Get-CMDeviceCollection -Name $name
}
catch {
    $module.FailJson("Failed to query device collection '$name': $($_.Exception.Message)", $_)
}

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
    $schedule_params_provided = @($schedule_recur_interval, $schedule_recur_count, $schedule_start) | Where-Object { $null -ne $_ }
    if ($schedule_params_provided.Count -gt 0 -and $schedule_params_provided.Count -lt 3) {
        $module.FailJson("All three schedule parameters must be provided together: schedule_recur_interval, schedule_recur_count, schedule_start.")
    }
    $has_schedule = ($schedule_params_provided.Count -eq 3)

    if ($has_schedule -and ($refresh_type -ne 'Periodic' -and $refresh_type -ne 'Both')) {
        $module.FailJson(
            "Schedule parameters (schedule_recur_interval, schedule_recur_count, schedule_start) " +
            "are only allowed when refresh_type is 'Periodic' or 'Both'."
        )
    }

    $schedule_start_dt = $null
    if ($has_schedule) {
        try {
            $schedule_start_dt = [datetime]::Parse($schedule_start)
        }
        catch {
            $module.FailJson("Invalid schedule_start value '$schedule_start'. Expected a valid date/time string, e.g. '2026-06-09 08:00'.")
        }

        $schedule_err = Assert-ScheduleParam -recurInterval $schedule_recur_interval -recurCount $schedule_recur_count
        if ($null -ne $schedule_err) {
            $module.FailJson($schedule_err)
        }
    }

    if ($null -eq $existing_dc) {
        if ([string]::IsNullOrEmpty($limiting_collection_name)) {
            $module.FailJson("'limiting_collection_name' is required when creating a new device collection.")
        }

        $module.result.changed = $true

        $effective_create_rt = if (-not [string]::IsNullOrEmpty($refresh_type)) { $refresh_type } else { 'Manual' }
        $create_params = @{
            Name = $name
            LimitingCollectionName = $limiting_collection_name
            RefreshType = $effective_create_rt
        }

        if ($has_schedule -and ($effective_create_rt -eq 'Periodic' -or $effective_create_rt -eq 'Both')) {
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

        if ($null -ne $dc_query_rules -or $null -ne $dc_direct_rules) {
            Sync-CollectionRule -module $module -collectionName $name `
                -desiredQueryRules $dc_query_rules -desiredDirectRules $dc_direct_rules `
                -collectionExists (-not $module.CheckMode)
        }

        if (-not $module.CheckMode) {
            try {
                $new_dc = Get-CMDeviceCollection -Name $name
            }
            catch {
                $module.FailJson("Failed to query device collection '$name': $($_.Exception.Message)", $_)
            }
            $module.result.device_collection = Format-DeviceCollectionResult -collection $new_dc
            $rules = Format-CollectionRulesResult -module $module -collectionName $name
            $module.result.device_collection.device_collection_query_rules = $rules.device_collection_query_rules
            $module.result.device_collection.device_collection_direct_rules = $rules.device_collection_direct_rules
        }
        else {
            $chk_query_rules = @()
            if ($null -ne $dc_query_rules) {
                $chk_query_rules = @(
                    foreach ($qr in $dc_query_rules) {
                        @{ rule_name = $qr.rule_name; query_expression = $qr.query_expression }
                    }
                )
            }
            $chk_direct_rules = @()
            if ($null -ne $dc_direct_rules) {
                $chk_direct_rules = @(
                    foreach ($dr in $dc_direct_rules) {
                        @{ resource_id = $dr.resource_id; rule_name = '' }
                    }
                )
            }
            $module.result.device_collection = @{
                name = $name
                collection_id = 'check_mode'
                limiting_collection_name = $limiting_collection_name
                refresh_type = $effective_create_rt
                member_count = 0
                comment = ''
                is_built_in = $false
                device_collection_query_rules = $chk_query_rules
                device_collection_direct_rules = $chk_direct_rules
            }
        }
    }
    else {
        $needs_update = $false
        $refresh_type_changed = $false
        $limiting_collection_changed = $false
        $schedule_changed = $false

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

        $effective_rt = if (-not [string]::IsNullOrEmpty($refresh_type)) { $refresh_type } else { $current_rt_str }

        if ($has_schedule -and ($effective_rt -eq 'Periodic' -or $effective_rt -eq 'Both')) {
            $sched = @($existing_dc.RefreshSchedule)[0]

            if ($null -eq $sched) {
                $schedule_changed = $true
            }
            else {
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

                $current_start_dt = $null
                $start_raw = $sched.StartTime
                if (-not [string]::IsNullOrEmpty($start_raw)) {
                    try {
                        $current_start_dt = [System.Management.ManagementDateTimeConverter]::ToDateTime($start_raw.ToString())
                    }
                    catch {
                        try {
                            $current_start_dt = [datetime]::Parse($start_raw.ToString())
                        }
                        catch {
                            Write-Verbose "Could not parse existing schedule start time '$start_raw': $($_.Exception.Message)"
                        }
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

        if ($null -ne $dc_query_rules -or $null -ne $dc_direct_rules) {
            Sync-CollectionRule -module $module -collectionName $name `
                -desiredQueryRules $dc_query_rules -desiredDirectRules $dc_direct_rules `
                -collectionExists $true
        }

        if (-not $module.CheckMode) {
            try {
                $updated_dc = Get-CMDeviceCollection -Name $name
            }
            catch {
                $module.FailJson("Failed to query device collection '$name': $($_.Exception.Message)", $_)
            }
            $module.result.device_collection = Format-DeviceCollectionResult -collection $updated_dc
            $rules = Format-CollectionRulesResult -module $module -collectionName $name
            $module.result.device_collection.device_collection_query_rules = $rules.device_collection_query_rules
            $module.result.device_collection.device_collection_direct_rules = $rules.device_collection_direct_rules
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
            if ($null -ne $dc_query_rules -or $null -ne $dc_direct_rules) {
                $chk_query_rules = @()
                if ($null -ne $dc_query_rules) {
                    $chk_query_rules = @(
                        foreach ($qr in $dc_query_rules) {
                            @{ rule_name = $qr.rule_name; query_expression = $qr.query_expression }
                        }
                    )
                }
                $chk_direct_rules = @()
                if ($null -ne $dc_direct_rules) {
                    $chk_direct_rules = @(
                        foreach ($dr in $dc_direct_rules) {
                            @{ resource_id = $dr.resource_id; rule_name = '' }
                        }
                    )
                }
                $module.result.device_collection.device_collection_query_rules = $chk_query_rules
                $module.result.device_collection.device_collection_direct_rules = $chk_direct_rules
            }
            else {
                $rules = Format-CollectionRulesResult -module $module -collectionName $name
                $module.result.device_collection.device_collection_query_rules = $rules.device_collection_query_rules
                $module.result.device_collection.device_collection_direct_rules = $rules.device_collection_direct_rules
            }
        }
    }
}

$module.ExitJson()

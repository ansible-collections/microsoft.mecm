#!powershell

# Copyright: (c) 2025, Ansible Project
# GNU General Public License v3.0+ (see COPYING or https://www.gnu.org/licenses/gpl-3.0.txt)

#AnsibleRequires -CSharpUtil Ansible.Basic
#AnsibleRequires -PowerShell ..module_utils._CMPsSetupUtils

$RUN_TYPE_MAP = @{
    'DoNotRunThisRuleAutomatically' = 0
    'RunTheRuleOnSchedule' = 1
    'RunTheRuleAfterAnySoftwareUpdatePointSynchronization' = 2
}

$VERBOSE_LEVEL_MAP = @{
    'AllMessages' = 10
    'OnlySuccessAndErrorMessages' = 5
    'OnlyErrorMessages' = 1
}

$SEVERITY_XML_MAP = @{
    'Critical' = "'10'"
    'Important' = "'8'"
    'Moderate' = "'4'"
    'Low' = "'2'"
    'None' = "'0'"
}


function Format-ADRResult {
    param (
        [Parameter(Mandatory = $true)][object]$adr
    )
    $current_run_type_str = Get-CurrentRunType -adr $adr
    return @{
        name = $adr.Name
        id = $adr.AutoDeploymentID.ToString()
        description = $adr.Description
        collection_id = $adr.CollectionID
        is_enabled = [bool]$adr.AutoDeploymentEnabled
        run_type = $RUN_TYPE_MAP[$current_run_type_str]
        last_run_time = Format-DateTimeAsStringSafely -dateTimeObject $adr.LastRunTime
    }
}


function Get-DeploymentTemplateProp {
    <#
    .SYNOPSIS
    Returns the text value of a named element from the DeploymentTemplate XML, or $null.
    #>
    param (
        [Parameter(Mandatory = $true)][object]$adr,
        [Parameter(Mandatory = $true)][string]$element_name
    )
    if ([string]::IsNullOrEmpty($adr.DeploymentTemplate)) {
        return $null
    }
    try {
        [xml]$xml = $adr.DeploymentTemplate
        return $xml.DeploymentCreationActionXML.$element_name
    }
    catch {
        return $null
    }
}


function Get-AutoDeploymentProp {
    <#
    .SYNOPSIS
    Returns the text value of a named element from the AutoDeploymentProperties XML, or $null.
    #>
    param (
        [Parameter(Mandatory = $true)][object]$adr,
        [Parameter(Mandatory = $true)][string]$element_name
    )
    if ([string]::IsNullOrEmpty($adr.AutoDeploymentProperties)) {
        return $null
    }
    try {
        [xml]$xml = $adr.AutoDeploymentProperties
        return $xml.AutoDeploymentRule.$element_name
    }
    catch {
        return $null
    }
}


function Get-CurrentRunType {
    <#
    .SYNOPSIS
    Derives the effective run_type string from the stored ADR properties.
    #>
    param (
        [Parameter(Mandatory = $true)][object]$adr
    )

    $align_with_sync = Get-AutoDeploymentProp -adr $adr -element_name 'AlignWithSyncSchedule'

    if ($align_with_sync -eq 'true') {
        return 'RunTheRuleAfterAnySoftwareUpdatePointSynchronization'
    }

    if (-not [string]::IsNullOrEmpty($adr.Schedule)) {
        return 'RunTheRuleOnSchedule'
    }

    return 'DoNotRunThisRuleAutomatically'
}


function Get-UpdateRuleXMLValue {
    <#
    .SYNOPSIS
    Extracts the MatchRules string list for a given PropertyName from UpdateRuleXML.
    #>
    param (
        [Parameter(Mandatory = $true)][object]$adr,
        [Parameter(Mandatory = $true)][string]$property_name
    )
    if ([string]::IsNullOrEmpty($adr.UpdateRuleXML)) {
        return @()
    }
    try {
        [xml]$xml = $adr.UpdateRuleXML
        $item = @($xml.UpdateXML.UpdateXMLDescriptionItems.UpdateXMLDescriptionItem) |
            Where-Object { $_.PropertyName -eq $property_name } |
            Select-Object -First 1
        if ($null -eq $item) {
            return @()
        }
        return @($item.MatchRules.string)
    }
    catch {
        return @()
    }
}


function Test-StringArraysDiffer {
    param (
        [AllowEmptyCollection()][string[]]$current,
        [AllowEmptyCollection()][string[]]$desired
    )
    $current_sorted = @($current | Sort-Object)
    $desired_sorted = @($desired | Sort-Object)
    if ($current_sorted.Count -ne $desired_sorted.Count) {
        return $true
    }
    for ($i = 0; $i -lt $current_sorted.Count; $i++) {
        if ($current_sorted[$i] -ne $desired_sorted[$i]) {
            return $true
        }
    }
    return $false
}


function Test-CategoryListChanged {
    <#
    .SYNOPSIS
    Compares a list of category display names against the GUID-based values.
    #>
    param (
        [AllowEmptyCollection()][Parameter(Mandatory = $true)][string[]]$desired_names,
        [AllowEmptyCollection()][Parameter(Mandatory = $true)][string[]]$xml_values,
        [Parameter(Mandatory = $true)][string]$cm_category_type
    )

    $current_ids = @($xml_values | ForEach-Object { $_.ToLower() })

    if ($current_ids.Count -ne $desired_names.Count) {
        return $true
    }

    try {
        $all_categories = @(Get-CMSoftwareUpdateCategory -CategoryTypeName $cm_category_type)
    }
    catch {
        return $true
    }

    $desired_ids = @()
    foreach ($name in $desired_names) {
        $match = $all_categories |
            Where-Object { $_.LocalizedCategoryInstanceName -ieq $name } |
            Select-Object -First 1
        if ($null -eq $match) {
            return $true
        }
        $desired_ids += $match.CategoryInstance_UniqueID.ToLower()
    }

    return Test-StringArraysDiffer -current $current_ids -desired $desired_ids
}


function Confirm-CMCategoryName {
    <#
    .SYNOPSIS
    Validates that all provided display names exist in the MECM software update catalog
    for the given category type.
    #>
    param (
        [Parameter(Mandatory = $true)][object]$module,
        [Parameter(Mandatory = $true)][string[]]$names,
        [Parameter(Mandatory = $true)][string]$category_type,
        [Parameter(Mandatory = $true)][string]$param_name
    )
    try {
        $all_categories = @(Get-CMSoftwareUpdateCategory -CategoryTypeName $category_type)
    }
    catch {
        $module.FailJson("Failed to query MECM software update categories for type '$category_type': $($_.Exception.Message)", $_)
    }
    foreach ($name in $names) {
        $found = $all_categories |
            Where-Object { $_.LocalizedCategoryInstanceName -ieq $name } |
            Select-Object -First 1
        if ($null -eq $found) {
            $available_names = $all_categories | Select-Object -ExpandProperty LocalizedCategoryInstanceName | Sort-Object
            $available = $available_names -join "', '"
            $module.FailJson("$param_name value '$name' was not found in the MECM catalog for type '$category_type'. " +
                "Available names: '$available'. " +
                "Ensure this product/classification is enabled in your Software Update Point synchronization settings.")
        }
    }
}


function New-ADRScheduleObject {
    <#
    .SYNOPSIS
    Builds a CMSchedule object from the schedule dict parameter.
    #>
    param (
        [Parameter(Mandatory = $true)][object]$module,
        [Parameter(Mandatory = $true)][hashtable]$schedule_dict
    )

    $schedule_ps_params = @{}

    $recur_count = $schedule_dict.recur_count
    if ($null -ne $recur_count) {
        $schedule_ps_params['RecurCount'] = $recur_count
    }

    $day_of_week = $schedule_dict.day_of_week
    if (-not [string]::IsNullOrEmpty($day_of_week)) {
        $schedule_ps_params['DayOfWeek'] = $day_of_week
    }
    elseif (-not [string]::IsNullOrEmpty($schedule_dict.recur_interval)) {
        $schedule_ps_params['RecurInterval'] = $schedule_dict.recur_interval
    }

    if (-not [string]::IsNullOrEmpty($schedule_dict.start)) {
        try {
            $schedule_ps_params['Start'] = [DateTime]::Parse($schedule_dict.start)
        }
        catch {
            $module.FailJson("Invalid schedule start value '$($schedule_dict.start)': $($_.Exception.Message)")
        }
    }

    try {
        return New-CMSchedule @schedule_ps_params
    }
    catch {
        $module.FailJson("Failed to create schedule object: $($_.Exception.Message)", $_)
    }
}


function Build-ADRCmdletParam {
    <#
    .SYNOPSIS
    Converts Ansible module parameters into a hashtable suitable for New/Set-CM* cmdlets.
    #>
    param (
        [Parameter(Mandatory = $true)][object]$module,
        [Parameter(Mandatory = $false)][bool]$is_new = $false
    )

    $params = @{}
    $direct_map = @{
        description = 'Description'
        enabled = 'Enable'
        add_to_existing_software_update_group = 'AddToExistingSoftwareUpdateGroup'
        deployment_package_name = 'DeploymentPackageName'
        run_type = 'RunType'
        available_time = 'AvailableTime'
        available_time_unit = 'AvailableTimeUnit'
        deadline_time = 'DeadlineTime'
        deadline_time_unit = 'DeadlineTimeUnit'
        allow_restart = 'AllowRestart'
        suppress_restart_server = 'SuppressRestartServer'
        suppress_restart_workstation = 'SuppressRestartWorkstation'
        allow_software_installation_outside_maintenance_window = 'AllowSoftwareInstallationOutsideMaintenanceWindow'
        allow_use_metered_network = 'AllowUseMeteredNetwork'
        download_from_microsoft_update = 'DownloadFromMicrosoftUpdate'
        use_branch_cache = 'UseBranchCache'
        user_notification = 'UserNotification'
        verbose_level = 'VerboseLevel'
        generate_success_alert = 'GenerateSuccessAlert'
        success_percentage = 'SuccessPercent'
        generate_failure_alert = 'GenerateFailureAlert'
        alert_time = 'AlertTime'
        alert_time_unit = 'AlertTimeUnit'
        use_utc = 'UseUtc'
        send_wakeup_packet = 'SendWakeupPacket'
        no_install_on_remote = 'NoInstallOnRemote'
        no_install_on_unprotected = 'NoInstallOnUnprotected'
        write_filter_handling = 'WriteFilterHandling'
        disable_operation_manager = 'DisableOperationManager'
        generate_operation_manager_alert = 'GenerateOperationManagerAlert'
        soft_deadline_enabled = 'SoftDeadlineEnabled'
        require_post_reboot_full_scan = 'RequirePostRebootFullScan'
    }

    $list_map = @{
        update_classification = 'UpdateClassification'
        product = 'Product'
        severity = 'Severity'
        article_id = 'ArticleId'
        title = 'Title'
    }

    foreach ($key in $direct_map.Keys) {
        if ($null -ne $module.Params.$key) {
            $params[$direct_map[$key]] = $module.Params.$key
        }
    }

    foreach ($key in $list_map.Keys) {
        if ($null -ne $module.Params.$key) {
            $params[$list_map[$key]] = $module.Params.$key
        }
    }

    if ($null -ne $module.Params.schedule) {
        $params['Schedule'] = New-ADRScheduleObject -module $module -schedule_dict $module.Params.schedule
    }

    return $params
}


function Test-ADRNeedsUpdate {
    <#
    .SYNOPSIS
    Returns $true when the desired state differs from the current ADR state.
    #>
    param (
        [Parameter(Mandatory = $true)][object]$module,
        [Parameter(Mandatory = $true)][object]$adr
    )

    if (($null -ne $module.Params.description) -and ($module.Params.description -ne $adr.Description)) {
        return $true
    }
    if (($null -ne $module.Params.enabled) -and ([bool]$module.Params.enabled -ne [bool]$adr.AutoDeploymentEnabled)) {
        return $true
    }
    if ($null -ne $module.Params.run_type) {
        $current_run_type = Get-CurrentRunType -adr $adr
        if ($module.Params.run_type -ne $current_run_type) {
            return $true
        }
    }

    $adp_bool_map = @{
        add_to_existing_software_update_group = 'UseSameDeployment'
        generate_failure_alert = 'EnableFailureAlert'
    }
    foreach ($param in $adp_bool_map.Keys) {
        if ($null -ne $module.Params.$param) {
            $current = Get-AutoDeploymentProp -adr $adr -element_name $adp_bool_map[$param]
            if ($null -ne $current) {
                if ([bool]$module.Params.$param -ne ($current -eq 'true')) {
                    return $true
                }
            }
        }
    }

    $dt_bool_map = @{
        use_utc = 'Utc'
        soft_deadline_enabled = 'SoftDeadlineEnabled'
        allow_restart = 'AllowRestart'
        disable_operation_manager = 'DisableMomAlert'
        generate_operation_manager_alert = 'GenerateMomAlert'
        use_branch_cache = 'UseBranchCache'
        send_wakeup_packet = 'EnableWakeOnLan'
        allow_software_installation_outside_maintenance_window = 'AllowInstallOutSW'
        generate_success_alert = 'EnableAlert'
        allow_use_metered_network = 'AllowUseMeteredNetwork'
        download_from_microsoft_update = 'AllowWUMU'
    }
    foreach ($param in $dt_bool_map.Keys) {
        if ($null -ne $module.Params.$param) {
            $current = Get-DeploymentTemplateProp -adr $adr -element_name $dt_bool_map[$param]
            if ($null -ne $current) {
                if ([bool]$module.Params.$param -ne ($current -eq 'true')) {
                    return $true
                }
            }
        }
    }

    if ($null -ne $module.Params.no_install_on_remote) {
        $current = Get-DeploymentTemplateProp -adr $adr -element_name 'UseRemoteDP'
        if ($null -ne $current) {
            $desired_use_remote = -not ([bool]$module.Params.no_install_on_remote)
            if ($desired_use_remote -ne ($current -eq 'true')) {
                return $true
            }
        }
    }
    if ($null -ne $module.Params.no_install_on_unprotected) {
        $current = Get-DeploymentTemplateProp -adr $adr -element_name 'UseUnprotectedDP'
        if ($null -ne $current) {
            $desired_use_unprotected = -not ([bool]$module.Params.no_install_on_unprotected)
            if ($desired_use_unprotected -ne ($current -eq 'true')) {
                return $true
            }
        }
    }

    $dt_checked_map = @{
        suppress_restart_server = 'SuppressServers'
        suppress_restart_workstation = 'SuppressWorkstations'
        write_filter_handling = 'PersistOnWriteFilterDevices'
        require_post_reboot_full_scan = 'RequirePostRebootFullScan'
    }
    foreach ($param in $dt_checked_map.Keys) {
        if ($null -ne $module.Params.$param) {
            $current = Get-DeploymentTemplateProp -adr $adr -element_name $dt_checked_map[$param]
            if ($null -ne $current) {
                if ([bool]$module.Params.$param -ne ($current -eq 'Checked')) {
                    return $true
                }
            }
        }
    }

    $dt_int_map = @{
        deadline_time = 'Duration'
        available_time = 'AvailableDeltaDuration'
        success_percentage = 'AlertThresholdPercentage'
        alert_time = 'AlertDuration'
    }
    foreach ($param in $dt_int_map.Keys) {
        if ($null -ne $module.Params.$param) {
            $current = Get-DeploymentTemplateProp -adr $adr -element_name $dt_int_map[$param]
            if ($null -ne $current) {
                if ([int]$module.Params.$param -ne [int]$current) {
                    return $true
                }
            }
        }
    }

    $dt_str_map = @{
        deadline_time_unit = 'DurationUnits'
        available_time_unit = 'AvailableDeltaDurationUnits'
        alert_time_unit = 'AlertDurationUnits'
        user_notification = 'UserNotificationOption'
    }
    foreach ($param in $dt_str_map.Keys) {
        if ($null -ne $module.Params.$param) {
            $current = Get-DeploymentTemplateProp -adr $adr -element_name $dt_str_map[$param]
            if ($null -ne $current) {
                if ($module.Params.$param -ne $current) {
                    return $true
                }
            }
        }
    }

    if ($null -ne $module.Params.verbose_level) {
        $current = Get-DeploymentTemplateProp -adr $adr -element_name 'StateMessageVerbosity'
        if ($null -ne $current) {
            if ($VERBOSE_LEVEL_MAP[$module.Params.verbose_level] -ne [int]$current) {
                return $true
            }
        }
    }

    $xml_direct_filter_map = @{
        article_id = 'ArticleID'
        title = 'Title'
    }
    foreach ($param in $xml_direct_filter_map.Keys) {
        if ($null -ne $module.Params.$param) {
            $current_values = @(Get-UpdateRuleXMLValue -adr $adr -property_name $xml_direct_filter_map[$param])
            if (Test-StringArraysDiffer -current $current_values -desired $module.Params.$param) {
                return $true
            }
        }
    }

    if ($null -ne $module.Params.severity) {
        $desired_codes = @($module.Params.severity | ForEach-Object { if ($SEVERITY_XML_MAP.ContainsKey($_)) { $SEVERITY_XML_MAP[$_] } else { $_ } })
        $current_codes = @(Get-UpdateRuleXMLValue -adr $adr -property_name 'Severity')
        if (Test-StringArraysDiffer -current $current_codes -desired $desired_codes) {
            return $true
        }
    }

    if ($null -ne $module.Params.update_classification) {
        $current_uc = @(Get-UpdateRuleXMLValue -adr $adr -property_name '_UpdateClassification')
        if (Test-CategoryListChanged -desired_names $module.Params.update_classification `
                -xml_values $current_uc -cm_category_type 'UpdateClassification') {
            return $true
        }
    }

    if ($null -ne $module.Params.product) {
        $current_product = @(Get-UpdateRuleXMLValue -adr $adr -property_name '_Product')
        if (Test-CategoryListChanged -desired_names $module.Params.product `
                -xml_values $current_product -cm_category_type 'Product') {
            return $true
        }
    }

    if ($null -ne $module.Params.deployment_package_name) {
        $current_pkg_id = $null
        if (-not [string]::IsNullOrEmpty($adr.ContentTemplate)) {
            try {
                [xml]$ct_xml = $adr.ContentTemplate
                $current_pkg_id = $ct_xml.ContentActionXML.PackageID
            }
            catch {
                $current_pkg_id = $null
            }
        }
        try {
            $desired_pkg = Get-CMSoftwareUpdateDeploymentPackage -Name $module.Params.deployment_package_name
            if ($null -eq $desired_pkg) {
                return $true
            }
            if ($desired_pkg.PackageID -ne $current_pkg_id) {
                return $true
            }
        }
        catch {
            return $true
        }
    }

    if ($null -ne $module.Params.schedule) {
        try {
            $desired_schedule_obj = New-ADRScheduleObject -module $module -schedule_dict $module.Params.schedule
            $desired_schedule_str = Convert-CMSchedule -InputObject $desired_schedule_obj
            if (-not [string]::IsNullOrEmpty($desired_schedule_str) -and $desired_schedule_str -ne $adr.Schedule) {
                return $true
            }
        }
        catch {
            $null = $_
        }
    }

    return $false
}


$spec = @{
    options = @{
        site_code = @{ type = 'str'; required = $true }
        name = @{ type = 'str'; required = $true }
        state = @{ type = 'str'; required = $false; default = 'present'; choices = @('present', 'absent') }
        collection_name = @{ type = 'str'; required = $false }
        description = @{ type = 'str'; required = $false }
        enabled = @{ type = 'bool'; required = $false }
        add_to_existing_software_update_group = @{ type = 'bool'; required = $false }
        deployment_package_name = @{ type = 'str'; required = $false }
        run_type = @{
            type = 'str'
            required = $false
            choices = @(
                'DoNotRunThisRuleAutomatically',
                'RunTheRuleAfterAnySoftwareUpdatePointSynchronization',
                'RunTheRuleOnSchedule'
            )
        }
        schedule = @{
            type = 'dict'
            required = $false
            options = @{
                recur_count = @{ type = 'int'; required = $false; default = 1 }
                recur_interval = @{
                    type = 'str'
                    required = $false
                    choices = @('Days', 'Hours', 'Minutes', 'Months', 'Weeks')
                }
                day_of_week = @{
                    type = 'str'
                    required = $false
                    choices = @('Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday')
                }
                week_order = @{
                    type = 'str'
                    required = $false
                    choices = @('First', 'Second', 'Third', 'Fourth', 'Last')
                }
                start = @{ type = 'str'; required = $false }
            }
        }
        update_classification = @{ type = 'list'; elements = 'str'; required = $false }
        product = @{ type = 'list'; elements = 'str'; required = $false }
        severity = @{ type = 'list'; elements = 'str'; required = $false }
        article_id = @{ type = 'list'; elements = 'str'; required = $false }
        title = @{ type = 'list'; elements = 'str'; required = $false }
        available_time = @{ type = 'int'; required = $false }
        available_time_unit = @{
            type = 'str'
            required = $false
            choices = @('Days', 'Hours', 'Minutes', 'Months', 'Weeks')
        }
        deadline_time = @{ type = 'int'; required = $false }
        deadline_time_unit = @{
            type = 'str'
            required = $false
            choices = @('Days', 'Hours', 'Minutes', 'Months', 'Weeks')
        }
        allow_restart = @{ type = 'bool'; required = $false }
        suppress_restart_server = @{ type = 'bool'; required = $false }
        suppress_restart_workstation = @{ type = 'bool'; required = $false }
        allow_software_installation_outside_maintenance_window = @{ type = 'bool'; required = $false }
        allow_use_metered_network = @{ type = 'bool'; required = $false }
        download_from_microsoft_update = @{ type = 'bool'; required = $false }
        use_branch_cache = @{ type = 'bool'; required = $false }
        user_notification = @{
            type = 'str'
            required = $false
            choices = @('DisplayAll', 'DisplaySoftwareCenterOnly', 'HideAll')
        }
        verbose_level = @{
            type = 'str'
            required = $false
            choices = @('AllMessages', 'OnlySuccessAndErrorMessages', 'OnlyErrorMessages')
        }
        generate_success_alert = @{ type = 'bool'; required = $false }
        success_percentage = @{ type = 'int'; required = $false }
        generate_failure_alert = @{ type = 'bool'; required = $false }
        alert_time = @{ type = 'int'; required = $false }
        alert_time_unit = @{
            type = 'str'
            required = $false
            choices = @('Days', 'Hours', 'Minutes', 'Months', 'Weeks')
        }
        use_utc = @{ type = 'bool'; required = $false }
        send_wakeup_packet = @{ type = 'bool'; required = $false }
        no_install_on_remote = @{ type = 'bool'; required = $false }
        no_install_on_unprotected = @{ type = 'bool'; required = $false }
        write_filter_handling = @{ type = 'bool'; required = $false }
        disable_operation_manager = @{ type = 'bool'; required = $false }
        generate_operation_manager_alert = @{ type = 'bool'; required = $false }
        soft_deadline_enabled = @{ type = 'bool'; required = $false }
        require_post_reboot_full_scan = @{ type = 'bool'; required = $false }
    }
    supports_check_mode = $true
}

$module = [Ansible.Basic.AnsibleModule]::Create($args, $spec)
$module.result.changed = $false
$module.result.software_update_adr = @{}

$site_code = $module.Params.site_code
$name = $module.Params.name
$state = $module.Params.state
$collection_name = $module.Params.collection_name

Import-CMPsModule -module $module
Test-CMSiteNameAndConnect -module $module -SiteCode $site_code

$existing_adr = Get-CMSoftwareUpdateAutoDeploymentRule -Name $name

if ($state -eq 'absent') {
    if ($null -ne $existing_adr) {
        $module.result.changed = $true
        $module.result.software_update_adr = Format-ADRResult -adr $existing_adr
        if (-not $module.CheckMode) {
            try {
                Remove-CMSoftwareUpdateAutoDeploymentRule -Name $name -Force -Confirm:$false
            }
            catch {
                $module.FailJson("Failed to remove Software Update ADR '$name': $($_.Exception.Message)", $_)
            }
        }
    }
}
elseif ($state -eq 'present') {
    if ($module.Params.run_type -eq 'RunTheRuleOnSchedule' -and $null -eq $module.Params.schedule) {
        $module.FailJson("O(schedule) is required when O(run_type) is 'RunTheRuleOnSchedule'. " +
            "Provide a schedule dict with at least one of: day_of_week, recur_interval.")
    }
    if ($null -ne $module.Params.schedule -and $module.Params.run_type -ne 'RunTheRuleOnSchedule') {
        $module.FailJson("O(schedule) must only be specified when O(run_type) is 'RunTheRuleOnSchedule'. " +
            "Remove the schedule parameter or set run_type to 'RunTheRuleOnSchedule'.")
    }

    if ($null -eq $existing_adr) {
        # Create new ADR
        if ([string]::IsNullOrEmpty($collection_name)) {
            $module.FailJson("O(collection_name) is required when creating a new Software Update ADR.")
        }

        $target_collection = Get-CMCollection -Name $collection_name
        if ($null -eq $target_collection) {
            $module.FailJson("Collection '$collection_name' was not found. Verify the collection name exists in MECM.")
        }

        if (-not [string]::IsNullOrEmpty($module.Params.deployment_package_name)) {
            $target_package = Get-CMSoftwareUpdateDeploymentPackage -Name $module.Params.deployment_package_name
            if ($null -eq $target_package) {
                $module.FailJson("Deployment package '$($module.Params.deployment_package_name)' was not found. Verify the package name exists in MECM.")
            }
        }

        if ($null -ne $module.Params.update_classification) {
            Confirm-CMCategoryName -module $module -names $module.Params.update_classification `
                -category_type 'UpdateClassification' -param_name 'update_classification'
        }

        if ($null -ne $module.Params.product) {
            Confirm-CMCategoryName -module $module -names $module.Params.product `
                -category_type 'Product' -param_name 'product'
        }

        if ($null -ne $module.Params.severity) {
            $valid_severities = @('None', 'Low', 'Moderate', 'Important', 'Critical')
            foreach ($sev in $module.Params.severity) {
                if ($sev -notin $valid_severities) {
                    $module.FailJson("severity value '$sev' is not valid. Allowed values: $($valid_severities -join ', ').")
                }
            }
        }

        $module.result.changed = $true

        if (-not $module.CheckMode) {
            $create_params = Build-ADRCmdletParam -module $module -is_new $true
            $create_params['Name'] = $name
            $create_params['Collection'] = $target_collection

            try {
                $null = New-CMSoftwareUpdateAutoDeploymentRule @create_params
            }
            catch {
                $module.FailJson("Failed to create Software Update ADR '$name': $($_.Exception.Message)", $_)
            }

            try {
                $new_adr = Get-CMSoftwareUpdateAutoDeploymentRule -Name $name
            }
            catch {
                $module.FailJson("Failed to retrieve newly created Software Update ADR '$name': $($_.Exception.Message)", $_)
            }
            if ($null -ne $new_adr) {
                $module.result.software_update_adr = Format-ADRResult -adr $new_adr
            }
        }
        else {
            $module.result.software_update_adr = @{
                name = $name
                id = 'check_mode'
                description = if ($null -ne $module.Params.description) { $module.Params.description } else { '' }
                collection_id = $target_collection.CollectionID
                is_enabled = $true
                run_type = if ($null -ne $module.Params.run_type) { $RUN_TYPE_MAP[$module.Params.run_type] } else { 0 }
                last_run_time = ''
            }
        }
    }
    else {
        # Update existing ADR
        $needs_update = Test-ADRNeedsUpdate -module $module -adr $existing_adr

        if ($needs_update) {
            $module.result.changed = $true

            if (-not $module.CheckMode) {
                $update_params = Build-ADRCmdletParam -module $module -is_new $false

                try {
                    $null = Set-CMSoftwareUpdateAutoDeploymentRule -Name $name @update_params -Confirm:$false -Force
                }
                catch {
                    $module.FailJson("Failed to update Software Update ADR '$name': $($_.Exception.Message)", $_)
                }
            }
        }

        if (-not $module.CheckMode) {
            try {
                $updated_adr = Get-CMSoftwareUpdateAutoDeploymentRule -Name $name
            }
            catch {
                $module.FailJson("Failed to retrieve updated Software Update ADR '$name': $($_.Exception.Message)", $_)
            }
            if ($null -ne $updated_adr) {
                $module.result.software_update_adr = Format-ADRResult -adr $updated_adr
            }
        }
        else {
            $cm_description = if ($null -ne $module.Params.description) { $module.Params.description } `
                else { $existing_adr.Description }
            $cm_is_enabled = if ($null -ne $module.Params.enabled) { [bool]$module.Params.enabled } `
                else { [bool]$existing_adr.AutoDeploymentEnabled }
            $cm_run_type = if ($null -ne $module.Params.run_type) { $RUN_TYPE_MAP[$module.Params.run_type] } `
                else { $RUN_TYPE_MAP[(Get-CurrentRunType -adr $existing_adr)] }
            $module.result.software_update_adr = @{
                name = $name
                id = $existing_adr.AutoDeploymentID.ToString()
                description = $cm_description
                collection_id = $existing_adr.CollectionID
                is_enabled = $cm_is_enabled
                run_type = $cm_run_type
                last_run_time = Format-DateTimeAsStringSafely -dateTimeObject $existing_adr.LastRunTime
            }
        }
    }
}

$module.ExitJson()

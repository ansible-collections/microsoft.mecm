#!powershell

# Copyright: (c) 2025, Ansible Project
# GNU General Public License v3.0+ (see COPYING or https://www.gnu.org/licenses/gpl-3.0.txt)

#AnsibleRequires -CSharpUtil Ansible.Basic
#AnsibleRequires -PowerShell ..module_utils._CMPsSetupUtils
#AnsibleRequires -PowerShell ..module_utils._GetObjectUtils


function Get-ObjectsForDeploymentInput {
    param (
        [Parameter(Mandatory = $true)][object]$module,
        [Parameter(Mandatory = $false)][boolean]$throw_error_if_not_found = $true
    )

    $software_group_id = $module.Params.software_update_group_id
    $software_group_name = $module.Params.software_update_group_name
    $software_update_id = $module.Params.software_update_id
    $software_update_name = $module.Params.software_update_name
    $collection_id = $module.Params.collection_id
    $collection_name = $module.Params.collection_name
    if (($null -ne $software_group_id) -or ($null -ne $software_group_name)) {
        $assigned_su_object = Get-SoftwareUpdateGroupObject `
            -module $module `
            -software_update_group_id $software_group_id `
            -software_update_group_name $software_group_name `
            -throw_error_if_not_found $throw_error_if_not_found
    }
    else {
        $assigned_su_object = Get-SoftwareUpdateObject `
            -module $module `
            -software_update_id $software_update_id `
            -software_update_name $software_update_name `
            -throw_error_if_not_found $throw_error_if_not_found
    }

    $targeted_collection = Get-CollectionObject `
        -module $module `
        -collection_id $collection_id `
        -collection_name $collection_name `
        -throw_error_if_not_found $throw_error_if_not_found

    return @{
        assigned_su_object = $assigned_su_object
        targeted_collection = $targeted_collection
    }
}


function Get-DeploymentObject {
    # Helper function to get a software update deployment object from the site, using module parameters as needed.
    param (
        [Parameter(Mandatory = $true)][object]$module
    )
    $deployment_object = $null
    if ($null -ne $module.Params.id) {
        $deployment_object = Get-CMSoftwareUpdateDeployment -DeploymentId $module.Params.id
    }
    else {
        $related_input_objects = Get-ObjectsForDeploymentInput -module $module -throw_error_if_not_found $false
        if (($null -eq $related_input_objects.assigned_su_object) -or ($null -eq $related_input_objects.targeted_collection)) {
            return $null
        }
        $deployment_object = Get-CMSoftwareUpdateDeployment `
            -InputObject $related_input_objects.assigned_su_object `
            -Collection $related_input_objects.targeted_collection
    }

    if ($deployment_object -is [array]) {
        $dIds = @()
        foreach ($deployment in $deployment_object) {
            $dIds += $deployment.AssignmentUniqueId
        }
        $module.FailJson(
            "Multiple deployments found for the given software and collection identifiers: $dIds. This module " +
            "only supports unique deployments. Please use the ID option to specify the deployment to manage."
        )
    }

    return $deployment_object
}


function Complete-DeploymentRemoval {
    # This function removes a software update deployment, if possible. It designed to be the main entry
    # point for the "absent" state.
    param (
        [Parameter(Mandatory = $true)][object]$module,
        [Parameter(Mandatory = $true)][AllowNull()][object]$deployment_object
    )
    if ($null -eq $deployment_object) {
        $module.ExitJson()
    }

    $module.result.changed = $true
    if (-not $module.CheckMode) {
        try {
            Remove-CMSoftwareUpdateDeployment -InputObject $deployment_object -Force
        }
        catch {
            $module.FailJson("Failed to remove deployment: $($_.Exception.Message)", $_)
        }
    }
    $module.ExitJson()
}


function Complete-DeploymentCreation {
    # This function creates a software update deployment. It is designed to be the main entry point for the
    # "present" state, when no deployment object is found.
    param (
        [Parameter(Mandatory = $true)][object]$module,
        [Parameter(Mandatory = $true)][hashtable]$direct_mapped_params,
        [Parameter(Mandatory = $true)][hashtable]$datetime_params,
        [Parameter(Mandatory = $true)][hashtable]$switch_params

    )

    $cmdlet_arguments = Format-ModuleParamAsCmdletArgument `
        -module $module `
        -direct_mapped_params $direct_mapped_params `
        -datetime_params $datetime_params `
        -switch_params $switch_params

    $allow_remote_distribution_point_downloads = $module.Params.allow_remote_distribution_point_downloads
    $allow_default_distribution_point_downloads = $module.Params.allow_default_distribution_point_downloads
    if ($null -ne $allow_remote_distribution_point_downloads) {
        $cmdlet_arguments.ProtectedType = $(If ($allow_remote_distribution_point_downloads) { "RemoteDistributionPoint" } Else { "NoInstall" })
    }
    if ($null -ne $allow_default_distribution_point_downloads) {
        $cmdlet_arguments.UnprotectedType = $(If ($allow_default_distribution_point_downloads) { "UnprotectedDistributionPoint" } Else { "NoInstall" })
    }

    $deployment_related_input_objects = Get-ObjectsForDeploymentInput -module $module
    Test-RequiredParametersForCreationModule -module $module -deployment_related_input_objects $deployment_related_input_objects
    $module.result.changed = $true
    if (-not $module.CheckMode) {
        try {
            $new_deployment_object = New-CMSoftwareUpdateDeployment `
                -InputObject $deployment_related_input_objects.assigned_su_object `
                -Collection $deployment_related_input_objects.targeted_collection `
                -AcceptEula `
                @cmdlet_arguments
        }
        catch {
            $module.FailJson("Failed to create deployment: $($_.Exception.Message)", $_)
        }

        if ($null -ne $module.Params.enabled) {
            Set-CMSoftwareUpdateDeployment -InputObject $new_deployment_object -Enable $module.Params.enabled
        }

        $module.result.software_update_deployment = @{
            name = $new_deployment_object.AssignmentName
            id = $new_deployment_object.AssignmentUniqueId
            assigned_software_update_ids = $new_deployment_object.AssignedCIs
            collection_id = $new_deployment_object.TargetCollectionID
        }
    }
}


function Complete-DeploymentUpdate {
    # This function updates a software update deployment if needed. It is designed to be the main entry point
    # for the "present" state, when an existing deployment object is found.
    param (
        [Parameter(Mandatory = $true)][object]$module,
        [Parameter(Mandatory = $true)][object]$deployment_object,
        [Parameter(Mandatory = $true)][hashtable]$direct_mapped_params,
        [Parameter(Mandatory = $true)][hashtable]$datetime_params,
        [Parameter(Mandatory = $true)][hashtable]$switch_params
    )
    # Massage the module parameter map to match the update cmdlet arguments
    $direct_mapped_params['name'] = 'NewDeploymentName'
    $direct_mapped_params['description'] = 'Description'
    $direct_mapped_params['allow_metered_network_downloads'] = 'AllowUseMeteredNetwork'
    $direct_mapped_params.remove('saved_package_id')
    $direct_mapped_params.remove('deploy_with_no_package')
    $direct_mapped_params.remove('distribution_collection_name')
    $direct_mapped_params.remove('distribution_point_group_name')
    $direct_mapped_params.remove('distribution_point_name')

    $switch_params.remove('distribute_content')

    $datetime_params['expiration_time'] = 'DeploymentExpireDateTime'

    $cmdlet_arguments = Format-ModuleParamAsCmdletArgument `
        -module $module `
        -direct_mapped_params $direct_mapped_params `
        -datetime_params $datetime_params `
        -switch_params $switch_params

    switch ($module.Params.allow_remote_distribution_point_downloads) {
        $true {
            $cmdlet_arguments.ProtectedType = "RemoteDistributionPoint"
        }
        $false {
            $cmdlet_arguments.ProtectedType = "NoInstall"
        }
        default {}
    }

    switch ($module.Params.allow_default_distribution_point_downloads) {
        $true {
            $cmdlet_arguments.UnprotectedType = "UnprotectedDistributionPoint"
        }
        $false {
            $cmdlet_arguments.UnprotectedType = "NoInstall"
        }
        default {}
    }

    if (Test-DeploymentNeedsUpdating -deployment_object $deployment_object -module $module) {
        $module.result.changed = $true
        if (-not $module.CheckMode) {
            try {
                Set-CMSoftwareUpdateDeployment `
                    -InputObject $deployment_object `
                    @cmdlet_arguments
            }
            catch {
                $module.FailJson("Failed to update deployment: $($_.Exception.Message)", $_)
            }
            $module.result.software_update_deployment = @{
                name = $deployment_object.AssignmentName
                id = $deployment_object.AssignmentUniqueId
                assigned_software_update_ids = $deployment_object.AssignedCIs
                collection_id = $deployment_object.TargetCollectionID
            }
        }
    }
}


function Test-RequiredParametersForCreationModule {
    # This function tests if the required module parameters are present for creation.
    param (
        [Parameter(Mandatory = $true)][object]$module,
        [Parameter(Mandatory = $true)][hashtable]$deployment_related_input_objects
    )
    if ($null -eq $module.Params.name) {
        $module.FailJson("Name must be specified when creating a deployment")
    }

    $assigned_su_object = $deployment_related_input_objects.assigned_su_object
    $targeted_collection = $deployment_related_input_objects.targeted_collection

    if ($null -eq $assigned_su_object) {
        $module.FailJson("A software update group or software update must be specified when creating a deployment")
    }

    if ($null -eq $targeted_collection) {
        $module.FailJson("A collection name or id must be specified when creating a deployment")
    }
}


function Test-DeploymentNeedsUpdating {
    # This function tests if the deployment needs to be updated.
    # Not all properties are exposed by the deployment object, so we need to check the subset of exposed properties
    # for changes, if the user has requested that. Otherwise we always return true to force an update.
    # Also, microsoft maps some properties to different values than the module parameters.
    # We need to handle these cases.
    param (
        [Parameter(Mandatory = $true)][object]$deployment_object,
        [Parameter(Mandatory = $true)][object]$module
    )
    if (-not $module.Params.only_use_verifiable_properties_for_change_detection) {
        return $true
    }

    $module_params_to_object_properties = @{
        description = "AssignmentDescription"
        name = "AssignmentName"
        disable_operations_manager_alerts = "DisableMomAlerts"
        enabled = "Enabled"
        persist_on_write_filter_device = "PersistOnWriteFilterDevices"
        generate_operations_manager_alert_on_failure = "RaiseMomAlertsOnFailure"
        allow_installation_outside_maintenance_window = "RebootOutsideOfServiceWindows"
        require_post_reboot_full_scan = "RequirePostRebootFullScan"
        enable_soft_deadline = "SoftDeadlineEnabled"
        use_branch_cache = "UseBranchCache"
        send_wake_up_packet = "WoLEnabled"
    }
    foreach ($module_param_name in $module_params_to_object_properties.Keys) {
        $param_value = $module.Params.$module_param_name
        $object_property_name = $module_params_to_object_properties[$module_param_name]
        if ($null -eq $param_value) {
            continue
        }
        if ($param_value -ne $deployment_object.$object_property_name) {
            return $true
        }
    }

    $available_time_param = $module.Params.available_time
    if ($null -ne $available_time_param) {
        if ($(Get-Date ($available_time_param)) -ne $deployment_object.StartTime) {
            return $true
        }
    }
    $expiration_time_param = $module.Params.expiration_time
    if ($null -ne $expiration_time_param) {
        if ($(Get-Date ($expiration_time_param)) -ne $deployment_object.EnforcementDeadline) {
            return $true
        }
    }

    # compare the weird attributes
    $user_notification_method_param = $module.Params.user_notification_method
    if ($null -ne $user_notification_method_param) {
        if ($user_notification_method_param -eq "DisplayAll" -and -not $deployment_object.NotifyUser) {
            return $true
        }
        if ($user_notification_method_param -eq "DisplaySoftwareCenterOnly" -and $deployment_object.NotifyUser) {
            return $true
        }
    }

    $timezone_param = $module.Params.deployment_timezone
    if ($null -ne $timezone_param) {
        if ($timezone_param -eq "utc" -and -not $deployment_object.UseGMTTimes) {
            return $true
        }
        if ($timezone_param -eq "local" -and $deployment_object.UseGMTTimes) {
            return $true
        }
    }

    $verbosity_param = $module.Params.deployment_verbosity
    if ($null -ne $verbosity_param) {
        switch ($verbosity_param) {
            "AllMessages" { $expected_value = 10 }
            "OnlySuccessAndErrorMessages" { $expected_value = 5 }
            "OnlyErrorMessages" { $expected_value = 1 }
        }
        if ($deployment_object.StateMessageVerbosity -ne $expected_value) {
            return $true
        }
    }

    $deployment_type_param = $module.Params.deployment_type
    if ($null -ne $deployment_type_param) {
        if ($deployment_type_param -eq "required" -and $deployment_object.SuppressReboot -ne 3) {
            return $true
        }
        if ($deployment_type_param -eq "available" -and $deployment_object.SuppressReboot -ne 0) {
            return $true
        }
    }

    return $false
}


$spec = @{
    options = @{
        site_code = @{ type = 'str'; required = $true }
        id = @{ type = 'str'; required = $false }
        state = @{ type = 'str'; required = $false ; choices = @("present", "absent"); default = "present" }
        only_use_verifiable_properties_for_change_detection = @{ type = 'bool'; required = $false; default = $false }

        software_update_group_id = @{ type = 'str'; required = $false }
        software_update_group_name = @{ type = 'str'; required = $false }
        software_update_id = @{ type = 'str'; required = $false }
        software_update_name = @{ type = 'str'; required = $false }
        collection_name = @{ type = 'str'; required = $false }
        collection_id = @{ type = 'str'; required = $false }

        name = @{ type = 'str'; required = $false }
        allow_restarts = @{ type = 'bool'; required = $false }
        allow_metered_network_downloads = @{ type = 'bool'; required = $false }
        allow_remote_distribution_point_downloads = @{ type = 'bool'; required = $false }
        allow_default_distribution_point_downloads = @{ type = 'bool'; required = $false }
        available_time = @{ type = 'str'; required = $false }
        expiration_time = @{ type = 'str'; required = $false }
        deployment_type = @{ type = 'str'; required = $false ; choices = @("required", "available") }
        description = @{ type = 'str'; required = $false }
        disable_operations_manager_alerts = @{ type = 'bool'; required = $false }
        generate_operations_manager_alert_on_failure = @{ type = 'bool'; required = $false }
        generate_success_threshold_alert = @{ type = 'bool'; required = $false }
        success_threshold = @{ type = 'int'; required = $false ; default = 95 }
        allow_microsoft_update_downloads = @{ type = 'bool'; required = $false }
        allow_branch_cache_downloads = @{ type = 'bool'; required = $false }
        enabled = @{ type = 'bool'; required = $false }
        persist_on_write_filter_device = @{ type = 'bool'; required = $false }
        require_post_reboot_full_scan = @{ type = 'bool'; required = $false }
        restart_servers_if_needed = @{ type = 'bool'; required = $false }
        restart_workstations_if_needed = @{ type = 'bool'; required = $false }
        send_wake_up_packet = @{ type = 'bool'; required = $false }
        enable_soft_deadline = @{ type = 'bool'; required = $false }
        allow_installation_outside_maintenance_window = @{ type = 'bool'; required = $false }
        deployment_timezone = @{ type = 'str'; required = $false ; choices = @("utc", "local") }
        user_notification_method = @{ type = 'str'; required = $false ; choices = @("DisplayAll", "DisplaySoftwareCenterOnly") }
        deployment_verbosity = @{ type = 'str'; required = $false ; choices = @("AllMessages", "OnlySuccessAndErrorMessages", "OnlyErrorMessages") }
        saved_package_id = @{ type = 'str'; required = $false }
        deploy_with_no_package = @{ type = 'bool'; required = $false; default = $true }
        distribute_content = @{ type = 'bool'; required = $false; default = $false }
        distribution_collection_name = @{ type = 'str'; required = $false }
        distribution_point_group_name = @{ type = 'str'; required = $false }
        distribution_point_name = @{ type = 'str'; required = $false }
    }
    supports_check_mode = $true
    required_one_of = @(
        , @("id", "software_update_group_id", "software_update_group_name", "software_update_id", "software_update_name")
        , @("id", "collection_name", "collection_id")
    )
    mutually_exclusive = @(
        , @("software_update_group_id", "software_update_group_name", "software_update_id", "software_update_name")
        , @("collection_name", "collection_id")
    )
    required_if = @(
        , @("deploy_with_no_package", $false, @("saved_package_id"), $false)
        , @("distribute_content", $true, @("distribution_collection_name", "distribution_point_group_name", "distribution_point_name"), $true)
    )
}

# Map one-to-one module parameters to cmdlet arguments
$DIRECT_MAPPED_PARAMS = @{
    allow_restarts = "AllowRestart"
    name = "DeploymentName"
    deployment_type = "DeploymentType"
    description = "Comment"
    disable_operations_manager_alerts = "DisableOperationsManagerAlert"
    allow_microsoft_update_downloads = "DownloadFromMicrosoftUpdate"
    generate_operations_manager_alert_on_failure = "GenerateOperationsManagerAlert"
    generate_success_threshold_alert = "GenerateSuccessAlert"
    success_threshold = "PercentSuccess"
    require_post_reboot_full_scan = "RequirePostRebootFullScan"
    restart_servers_if_needed = "RestartServer"
    restart_workstations_if_needed = "RestartWorkstation"
    enable_soft_deadline = "SoftDeadlineEnabled"
    allow_installation_outside_maintenance_window = "SoftwareInstallation"
    deployment_timezone = "TimeBasedOn"
    allow_branch_cache_downloads = "UseBranchCache"
    user_notification_method = "UserNotification"
    deployment_verbosity = "VerbosityLevel"
    saved_package_id = "SavedPackageId"
    deploy_with_no_package = "DeployWithNoPackage"
    distribution_collection_name = "DistributionCollectionName"
    distribution_point_group_name = "DistributionPointGroupName"
    distribution_point_name = "DistributionPointName"
    persist_on_write_filter_device = "PersistOnWriteFilterDevice"
    send_wake_up_packet = "SendWakeupPacket"
    allow_metered_network_downloads = "UseMeteredNetwork"
}

# Map module parameters that are string that should be cast to datetime cmdlet arguments
$DATETIME_PARAMS = @{
    available_time = "AvailableDateTime"
    expiration_time = "DeadlineDateTime"
}

# Map module parameters that are booleans that should be cast to switch cmdlet arguments
$SWITCH_PARAMS = @{
    distribute_content = "DistributeContent"
}

$module = [Ansible.Basic.AnsibleModule]::Create($args, $spec)
$module.result.software_update_deployment = @{}
$module.result.changed = $false

# Map frequently used module parameters to cmdlet arguments
$site_code = $module.Params.site_code
$state = $module.Params.state

# Setup PS environment
Import-CMPsModule -module $module
if (Test-CMSiteDrive -SiteCode $site_code) {
    Set-Location -LiteralPath "$($site_code):\"
}
else {
    $module.FailJson("Failed to find the site PS drive for site code $($site_code)")
}

# Lookup the deployment object and seed the result object
$deployment_object = Get-DeploymentObject -module $module
if ($null -ne $deployment_object) {
    $module.result.software_update_deployment = @{
        name = $deployment_object.AssignmentName
        id = $deployment_object.AssignmentUniqueId
        assigned_software_update_ids = $deployment_object.AssignedCIs
        collection_id = $deployment_object.TargetCollectionID
    }
}

# Route to the appropriate function based on desired state and current object state
if ($state -eq "absent") {
    Complete-DeploymentRemoval -module $module -deployment_object $deployment_object
}
elseif ($null -eq $deployment_object) {
    Complete-DeploymentCreation -module $module `
        -direct_mapped_params $DIRECT_MAPPED_PARAMS `
        -datetime_params $DATETIME_PARAMS `
        -switch_params $SWITCH_PARAMS
}
else {
    Complete-DeploymentUpdate -module $module `
        -deployment_object $deployment_object `
        -direct_mapped_params $DIRECT_MAPPED_PARAMS `
        -datetime_params $DATETIME_PARAMS `
        -switch_params $SWITCH_PARAMS
}

$module.ExitJson()

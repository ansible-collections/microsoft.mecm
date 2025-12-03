#!powershell

# Copyright: (c) 2025, Ansible Project
# GNU General Public License v3.0+ (see COPYING or https://www.gnu.org/licenses/gpl-3.0.txt)

#AnsibleRequires -CSharpUtil Ansible.Basic
#AnsibleRequires -PowerShell ..module_utils._CMPsSetupUtils
#AnsibleRequires -PowerShell ..module_utils._GetObjectUtils



function Get-CmdletArgsForDeploymentQuery {
    param (
        [Parameter(Mandatory = $true)][object]$module
    )
    $software_update_group_id = $module.Params.software_update_group_id
    $software_update_group_name = $module.Params.software_update_group_name
    $software_update_id = $module.Params.software_update_id
    $software_update_name = $module.Params.software_update_name
    $collection_id = $module.Params.collection_id
    $collection_name = $module.Params.collection_name
    $cmdlet_args = @{}

    if (($null -ne $software_update_group_id) -or ($null -ne $software_update_group_name)) {
        $software_object = Get-SoftwareUpdateGroupObject `
            -module $module `
            -software_update_group_id $software_update_group_id `
            -software_update_group_name $software_update_group_name `
            -throw_error_if_not_found $true
        $cmdlet_args["InputObject"] = $software_object
    }
    elseif (($null -ne $software_update_id) -or ($null -ne $software_update_name)) {
        $software_object = Get-SoftwareUpdateObject `
            -module $module `
            -software_update_id $software_update_id `
            -software_update_name $software_update_name `
            -throw_error_if_not_found $true
        $cmdlet_args["InputObject"] = $software_object
    }

    if (($null -ne $collection_id) -or ($null -ne $collection_name)) {
        $collection_object = Get-CollectionObject `
            -module $module `
            -collection_id $collection_id `
            -collection_name $collection_name `
            -throw_error_if_not_found $true
        $cmdlet_args["Collection"] = $collection_object
    }

    return $cmdlet_args
}


$spec = @{
    options = @{
        site_code = @{ type = 'str'; required = $true }
        id = @{ type = 'str'; required = $false }

        software_update_group_id = @{ type = 'str'; required = $false }
        software_update_group_name = @{ type = 'str'; required = $false }
        software_update_id = @{ type = 'str'; required = $false }
        software_update_name = @{ type = 'str'; required = $false }
        collection_name = @{ type = 'str'; required = $false }
        collection_id = @{ type = 'str'; required = $false }
    }
    supports_check_mode = $true
    mutually_exclusive = @(
        , @("software_update_group_id", "software_update_group_name", "software_update_id", "software_update_name")
        , @("collection_name", "collection_id")
    )
}


$module = [Ansible.Basic.AnsibleModule]::Create($args, $spec)
$module.result.software_update_deployments = @()
$module.result.changed = $false

# Map frequently used module parameters to cmdlet arguments
$site_code = $module.Params.site_code

# Setup PS environment
Import-CMPsModule -module $module
Test-CMSiteNameAndConnect -SiteCode $site_code -Module $module

# Lookup deployments
$deployment_objects = @()
if (-not [string]::IsNullOrEmpty($module.Params.id)) {
    $deployment_objects += Get-CMSoftwareUpdateDeployment -DeploymentId $module.Params.id
}
else {
    $cmdlet_args = Get-CmdletArgsForDeploymentQuery -module $module
    $search_results = Get-CMSoftwareUpdateDeployment @cmdlet_args
    if ($search_results -is [array]) {
        $deployment_objects = $search_results
    }
    else {
        $deployment_objects += $search_results
    }
}

# Format the results
foreach ($deployment_object in $deployment_objects) {
    if ($null -eq $deployment_object) {
        continue
    }
    $module.result.software_update_deployments += @{
        name = $deployment_object.AssignmentName
        id = $deployment_object.AssignmentUniqueId
        assigned_software_update_ids = $deployment_object.AssignedCIs
        collection_id = $deployment_object.TargetCollectionID
        description = $deployment_object.AssignmentDescription
        enabled = $deployment_object.Enabled
        persist_on_write_filter_device = $deployment_object.PersistOnWriteFilterDevices
        generate_operations_manager_alert_on_failure = $deployment_object.RaiseMomAlertsOnFailure
        allow_installation_outside_maintenance_window = $deployment_object.RebootOutsideOfServiceWindows
        require_post_reboot_full_scan = $deployment_object.RequirePostRebootFullScan
        enable_soft_deadline = $deployment_object.SoftDeadlineEnabled
        use_branch_cache = $deployment_object.UseBranchCache
        send_wake_up_packet = $deployment_object.WoLEnabled
        disable_operations_manager_alerts = $deployment_object.DisableMomAlerts
        creation_time = Format-DateTimeAsStringSafely -dateTimeObject $deployment_object.CreationTime
        last_modified_by = $deployment_object.LastModifiedBy
        last_modified_time = Format-DateTimeAsStringSafely -dateTimeObject $deployment_object.LastModificationTime
        available_time = Format-DateTimeAsStringSafely -dateTimeObject $deployment_object.StartTime
        expiration_time = Format-DateTimeAsStringSafely -dateTimeObject $deployment_object.DeadlineDateTime
        timezone = if ($deployment_object.UseGMTTimes) { "utc" } else { "localtime" }
        deployment_type = if ($deployment_object.SuppressReboot -eq 3) { "required" } else { "available" }
        contains_expired_updates = $deployment_object.ContainsExpiredUpdates
    }
}

$module.ExitJson()

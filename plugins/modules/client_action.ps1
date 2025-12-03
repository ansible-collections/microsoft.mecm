#!powershell

# Copyright: (c) 2025, Ansible Project
# GNU General Public License v3.0+ (see COPYING or https://www.gnu.org/licenses/gpl-3.0.txt)

#AnsibleRequires -CSharpUtil Ansible.Basic
#AnsibleRequires -PowerShell ..module_utils._CMPsSetupUtils
#AnsibleRequires -PowerShell ..module_utils._GetObjectUtils


$spec = @{
    options = @{
        device_name = @{ type = 'str'; required = $false }
        device_id = @{ type = 'str'; required = $false }
        collection_name = @{ type = 'str'; required = $false }
        collection_id = @{ type = 'str'; required = $false }
        site_code = @{ type = 'str'; required = $true }
        action = @{
            type = 'str'; required = $true; choices = @(
                "EndpointProtectionFullScan"
                "EndpointProtectionQuickScan"
                "EndpointProtectionDownloadDefinition"
                "EndpointProtectionEvaluateSoftwareUpdate"
                "EndpointProtectionExcludeScanPaths"
                "EndpointProtectionAllowThreat"
                "EndpointProtectionRestoreQuarantinedItems"
                "ClientNotificationRequestMachinePolicyNow"
                "ClientNotificationRequestUsersPolicyNow"
                "ClientNotificationRequestDDRNow"
                "ClientNotificationRequestSWInvNow"
                "ClientNotificationRequestHWInvNow"
                "ClientNotificationAppDeplEvalNow"
                "ClientNotificationSUMDeplEvalNow"
                "ClientRequestSUPChangeNow"
                "ClientRequestDHAChangeNow"
                "ClientNotificationRebootMachine"
                "DiagnosticsEnableVerboseLogging"
                "DiagnosticsDisableVerboseLogging"
                "DiagnosticsCollectFiles"
                "EndpointProtectionRestoreWithDeps"
                "ClientNotificationCheckComplianceNow"
                "RequestScriptExecution"
                "RequestCMPivotExecution"
                "ClientNotificationWakeUpClientNow"
                "RequestMachinePolicyNow"
                "RequestUsersPolicyNow"
            )
        }
    }
    supports_check_mode = $false
    required_one_of = @(
        , @("device_name", "device_id", "collection_name", "collection_id")
    )
    mutually_exclusive = @(
        , @("device_name", "device_id", "collection_name", "collection_id")
    )
}


$module = [Ansible.Basic.AnsibleModule]::Create($args, $spec)
$module.result.changed = $true

# Map frequently used module parameters to cmdlet arguments
$NOTIFICATION_TYPE_ACTIONS = @("RequestMachinePolicyNow", "RequestUsersPolicyNow")
$site_code = $module.Params.site_code
$action = $module.Params.action
$device_name = $module.Params.device_name
$device_id = $module.Params.device_id
$collection_name = $module.Params.collection_name
$collection_id = $module.Params.collection_id

# Setup PS environment
Import-CMPsModule -module $module
Test-CMSiteNameAndConnect -SiteCode $site_code -Module $module

# Lookup the target client(s). Either device or collection identifiers were provided
$cmdlet_arguments = @{}
if (($null -ne $device_name) -or ($null -ne $device_id)) {
    $cmdlet_arguments['Device'] = Get-ClientDeviceObject `
        -module $module `
        -device_name $device_name `
        -device_id $device_id `
        -throw_error_if_not_found $true
}
else {
    $cmdlet_arguments['Collection'] = Get-CollectionObject `
        -module $module `
        -collection_name $collection_name `
        -collection_id $collection_id `
        -throw_error_if_not_found $true
}


# Route to the appropriate function based on desired state and current object state
if ($NOTIFICATION_TYPE_ACTIONS -contains "$action") {
    $cmdlet_arguments['NotificationType'] = $action
}
else {
    $cmdlet_arguments['ActionType'] = $action
}

try {
    Invoke-CMClientAction @cmdlet_arguments
}
catch {
    $module.FailJson("Failed to start client action: $($_.Exception.Message)", $_)
}

$module.ExitJson()

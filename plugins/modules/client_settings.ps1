#!powershell

# Copyright: (c) 2025, Ansible Project
# GNU General Public License v3.0+ (see COPYING or https://www.gnu.org/licenses/gpl-3.0.txt)

#AnsibleRequires -CSharpUtil Ansible.Basic
#AnsibleRequires -PowerShell ..module_utils._CMPsSetupUtils
#AnsibleRequires -PowerShell ..module_utils._ClientSettingUtils


$CLIENT_SETTING_TYPE_CMDLET = @{
    device = 'Device'
    user = 'User'
}


# Maps each user-selectable custom setting name to one or more agent configuration entries.
$CUSTOM_SETTING_MAP = @{
    BackgroundIntelligentTransfer = @(
        @{ agent_id = 11; class = 'SMS_BITS2Config'; defaults = @{ EnableBitsMaxBandwidth = $false } }
    )
    ClientCache = @(
        @{ agent_id = 6; class = 'SMS_SoftwareDistributionAgentConfig'; defaults = @{ CacheTombstoneContentMinDuration = 86400 } },
        @{ agent_id = 27; class = 'SMS_WinPEPeerCacheConfig'; defaults = @{ BranchCacheEnabled = $false } },
        @{ agent_id = 31; class = 'SMS_PeerPxeConfig'; defaults = @{ EnablePeerPxe = $false } }
    )
    ClientPolicy = @(
        @{ agent_id = 13; class = 'SMS_PolicyAgentConfig'; defaults = @{ PolicyEnableUserPolicyPolling = $true } }
    )
    CloudService = @(
        @{ agent_id = 22; class = 'SMS_CloudAgentConfig'; defaults = @{ AllowCMG = $true } }
    )
    ComplianceSettings = @(
        @{ agent_id = 1; class = 'SMS_DCMAgentConfig'; defaults = @{ Enabled = $true } }
    )
    ComputerAgent = @(
        @{ agent_id = 4; class = 'SMS_ConfigMgrClientAgentConfig'; defaults = @{ AllowPortalToHaveElevatedTrust = $true } },
        @{ agent_id = 25; class = 'SMS_ClientResourcesConfig'; defaults = @{ DisableGlobalRandomization = $true } }
    )
    ComputerRestart = @(
        @{ agent_id = 21; class = 'SMS_ClientRestartAgentConfig'; defaults = @{ EnforceReboot = $true } }
    )
    DeliveryOptimization = @(
        @{ agent_id = 32; class = 'SMS_WindowsDOConfig'; defaults = @{ EnableWindowsDO = $false } }
    )
    EndpointProtection = @(
        @{ agent_id = 20; class = 'SMS_EndpointProtectionAgentConfig'; defaults = @{ DisableFirstSignatureUpdate = $true } }
    )
    Enrollment = @(
        @{ agent_id = 12; class = 'SMS_MobileDeviceAgentConfig'; defaults = @{ MDMPollInterval = 1440 } }
    )
    HardwareInventory = @(
        @{ agent_id = 15; class = 'SMS_HardwareInventoryAgentConfig'; defaults = @{ Enabled = $true } }
    )
    MeteredInternetConnection = @(
        @{ agent_id = 23; class = 'SMS_ClientCommunicationConfig'; defaults = @{ MeteredNetworkUsage = 4 } }
    )
    PowerManagement = @(
        @{ agent_id = 18; class = 'SMS_PowerAgentConfig'; defaults = @{ Enabled = $true } }
    )
    RemoteTools = @(
        @{ agent_id = 3; class = 'SMS_RemoteToolsAgentConfig'; defaults = @{ AllowLocalAdminToDoRemoteControl = $true } }
    )
    SoftwareCenter = @(
        @{ agent_id = 30; class = 'SMS_SoftwareCenterConfig'; defaults = @{ SC_Old_Branding = 0 } }
    )
    SoftwareDeployment = @(
        @{ agent_id = 17; class = 'SMS_ApplicationManagementAgentConfig'; defaults = @{ AppXInplaceUpgradeEnabled = $false } }
    )
    SoftwareInventory = @(
        @{ agent_id = 2; class = 'SMS_SoftwareInventoryAgentConfig'; defaults = @{ Enabled = $true } }
    )
    SoftwareMetering = @(
        @{ agent_id = 8; class = 'SMS_SoftwareMeteringAgentConfig'; defaults = @{ Enabled = $true } }
    )
    SoftwareUpdate = @(
        @{ agent_id = 9; class = 'SMS_SoftwareUpdatesAgentConfig'; defaults = @{ Enabled = $true } }
    )
    StateMessaging = @(
        @{ agent_id = 16; class = 'SMS_StateSystemConfig'; defaults = @{ BulkSendInterval = 15 } }
    )
    UserAndDeviceAffinity = @(
        @{ agent_id = 10; class = 'SMS_TargetingAgentConfig'; defaults = @{ ConsoleMinutes = 2880 } }
    )
    WindowsAnalytics = @(
        @{ agent_id = 29; class = 'SMS_WindowsAnalyticsConfig'; defaults = @{ WATelLevel = 1 } }
    )
}


function Build-OverrideConfig {
    param (
        [Parameter(Mandatory = $true)][object]$ConnectionManager,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$SettingNames
    )
    $i_result_object_type = [Microsoft.ConfigurationManagement.ManagementProvider.IResultObject]
    $override_configs = New-Object "System.Collections.Generic.List``1[$i_result_object_type]"
    foreach ($setting_name in $SettingNames) {
        foreach ($agent in $CUSTOM_SETTING_MAP[$setting_name]) {
            $native_new_ob = $ConnectionManager.CreateEmbeddedObjectInstance($agent.class)
            $native_new_ob['AgentID'].IntegerValue = $agent.agent_id
            foreach ($key in $agent.defaults.Keys) {
                $value = $agent.defaults[$key]
                if ($value -is [bool]) {
                    $native_new_ob[$key].BooleanValue = $value
                }
                else {
                    $native_new_ob[$key].IntegerValue = $value
                }
            }
            $null = $override_configs.Add($native_new_ob)
        }
    }
    return , $override_configs
}


function Set-CustomSetting {
    param (
        [Parameter(Mandatory = $true)][string]$name,
        [Parameter(Mandatory = $true)][string]$type,
        [Parameter(Mandatory = $false)][AllowNull()][string[]]$custom_device_settings,
        [Parameter(Mandatory = $false)][AllowNull()][string[]]$custom_user_settings,
        [Parameter(Mandatory = $true)][bool]$check_mode
    )
    $desired_settings = if ($type -eq 'device') { $custom_device_settings } else { $custom_user_settings }

    if ($null -ne $desired_settings -and $desired_settings.Count -eq 0) {
        return $false
    }

    if ($null -eq $desired_settings) {
        $wmi_check = Get-CMClientSetting -Name $name
        $null = $wmi_check.Get()
        $current_raw = $wmi_check.Properties.AgentConfigurations.AgentID
        $current_agent_ids = @(if ($null -ne $current_raw) { $current_raw | ForEach-Object { [int]$_ } })
        if ($current_agent_ids.Count -eq 0) {
            return $false
        }
        if (-not $check_mode) {
            $wmi_setting = Get-CMClientSetting -Name $name
            $i_result_object_type = [Microsoft.ConfigurationManagement.ManagementProvider.IResultObject]
            $override_configs = New-Object "System.Collections.Generic.List``1[$i_result_object_type]"
            $wmi_setting.SetArrayItems('AgentConfigurations', $override_configs)
            $null = $wmi_setting.Put()
        }
        return $true
    }

    $desired_agent_ids = @(foreach ($s in $desired_settings) { foreach ($a in $CUSTOM_SETTING_MAP[$s]) { $a.agent_id } })
    $current_raw = (Get-CMClientSetting -Name $name).Properties.AgentConfigurations.AgentID
    $current_agent_ids = @(if ($null -ne $current_raw) { $current_raw | ForEach-Object { [int]$_ } })

    $to_add = @($desired_agent_ids | Where-Object { $_ -notin $current_agent_ids })
    $to_remove = @($current_agent_ids | Where-Object { $_ -notin $desired_agent_ids })

    if ($to_add.Count -eq 0 -and $to_remove.Count -eq 0) {
        return $false
    }

    if (-not $check_mode) {
        $wmi_setting = Get-CMClientSetting -Name $name
        $override_configs = Build-OverrideConfig -ConnectionManager $wmi_setting.ConnectionManager -SettingNames $desired_settings
        $wmi_setting.SetArrayItems('AgentConfigurations', $override_configs)
        $null = $wmi_setting.Put()
    }

    return $true
}


function Set-ClientSettingPriority {
    param (
        [Parameter(Mandatory = $true)][string]$name,
        [Parameter(Mandatory = $true)][int]$priority
    )
    $wmi_setting = Get-CMClientSetting -Name $name
    $null = $wmi_setting.Get()
    $wmi_setting.Priority = $priority
    $null = $wmi_setting.Put()
}


$spec = @{
    options = @{
        site_code = @{ type = 'str'; required = $true }
        name = @{ type = 'str'; required = $true }
        type = @{
            type = 'str'
            required = $true
            choices = @('device', 'user')
        }
        description = @{ type = 'str'; required = $false }
        priority = @{ type = 'int'; required = $false }
        custom_device_settings = @{
            type = 'list'
            elements = 'str'
            required = $false
            default = 'system'
            choices = @(
                'system',
                'BackgroundIntelligentTransfer', 'ClientCache', 'ClientPolicy', 'CloudService',
                'ComplianceSettings', 'ComputerAgent', 'ComputerRestart', 'DeliveryOptimization',
                'EndpointProtection', 'Enrollment', 'HardwareInventory', 'MeteredInternetConnection',
                'PowerManagement', 'RemoteTools', 'SoftwareCenter', 'SoftwareDeployment',
                'SoftwareInventory', 'SoftwareMetering', 'SoftwareUpdate', 'StateMessaging',
                'UserAndDeviceAffinity', 'WindowsAnalytics'
            )
        }
        custom_user_settings = @{
            type = 'list'
            elements = 'str'
            required = $false
            default = 'system'
            choices = @('system', 'CloudService', 'Enrollment', 'UserAndDeviceAffinity')
        }
        state = @{
            type = 'str'
            required = $false
            default = 'present'
            choices = @('present', 'absent')
        }
    }
    supports_check_mode = $true
}

$module = [Ansible.Basic.AnsibleModule]::Create($args, $spec)
$module.result.changed = $false
$module.result.client_setting = @{}

$site_code = $module.Params.site_code
$name = $module.Params.name
$type = $module.Params.type
$description = $module.Params.description
$priority = $module.Params.priority
$custom_device_settings = $module.Params.custom_device_settings
$custom_user_settings = $module.Params.custom_user_settings
$state = $module.Params.state

$_system_msg = "Use 'system' alone to leave settings unchanged, or omit the parameter entirely."
if ($null -ne $custom_device_settings -and $custom_device_settings -contains 'system' -and $custom_device_settings.Count -gt 1) {
    $module.FailJson("'system' cannot be combined with other choices in custom_device_settings. $_system_msg")
}
if ($null -ne $custom_user_settings -and $custom_user_settings -contains 'system' -and $custom_user_settings.Count -gt 1) {
    $module.FailJson("'system' cannot be combined with other choices in custom_user_settings. $_system_msg")
}

$device_omitted = $null -eq $custom_device_settings -or $custom_device_settings -contains 'system'
$user_omitted = $null -eq $custom_user_settings -or $custom_user_settings -contains 'system'

if ($null -ne $custom_device_settings) {
    $custom_device_settings = @($custom_device_settings | Where-Object { $_ -ne 'system' })
}
if ($null -ne $custom_user_settings) {
    $custom_user_settings = @($custom_user_settings | Where-Object { $_ -ne 'system' })
}

if (-not $device_omitted -and $type -ne 'device') {
    $module.FailJson("Parameter 'custom_device_settings' is only valid when type is 'device'.")
}
if (-not $user_omitted -and $type -ne 'user') {
    $module.FailJson("Parameter 'custom_user_settings' is only valid when type is 'user'.")
}

Import-CMPsModule -module $module
Test-CMSiteNameAndConnect -module $module -SiteCode $site_code

$client_setting = Get-CMClientSetting -Name $name -ErrorAction SilentlyContinue

if ($state -eq 'absent') {
    if ($null -ne $client_setting) {
        try {
            $null = Remove-CMClientSetting -Name $name -Force -Confirm:$false -WhatIf:$module.CheckMode
        }
        catch {
            $module.FailJson("Failed to remove client setting '$name': $($_.Exception.Message)", $_)
        }
        $module.result.changed = $true
        $module.result.client_setting = Format-ClientSettingResult -setting $client_setting
    }
}
elseif ($state -eq 'present') {
    if ($null -eq $client_setting) {
        $create_params = @{
            Name = $name
            Type = $CLIENT_SETTING_TYPE_CMDLET[$type]
        }
        if ($null -ne $description) {
            $create_params['Description'] = $description
        }

        try {
            $null = New-CMClientSetting @create_params -WhatIf:$module.CheckMode
        }
        catch {
            $module.FailJson("Failed to create client setting '$name': $($_.Exception.Message)", $_)
        }

        $module.result.changed = $true

        if (-not $module.CheckMode) {
            if ($null -ne $priority) {
                try {
                    Set-ClientSettingPriority -name $name -priority $priority
                }
                catch {
                    $module.FailJson("Failed to set priority for client setting '$name': $($_.Exception.Message)", $_)
                }
            }

            $_has_cds = -not $device_omitted -and $custom_device_settings.Count -gt 0
            $_has_cus = -not $user_omitted -and $custom_user_settings.Count -gt 0
            if ($_has_cds -or $_has_cus) {
                try {
                    $null = Set-CustomSetting -name $name -type $type `
                        -custom_device_settings $custom_device_settings `
                        -custom_user_settings $custom_user_settings `
                        -check_mode $module.CheckMode
                }
                catch {
                    $module.FailJson("Failed to apply custom settings for client setting '$name': $($_.Exception.Message)", $_)
                }
            }

            $client_setting = Get-CMClientSetting -Name $name
            $module.result.client_setting = Format-ClientSettingResult -setting $client_setting
        }
    }
    else {
        $type_int = [int]$client_setting.Type
        $current_type = ConvertTo-ClientSettingTypeString -TypeInt $type_int
        if ($type -ne $current_type) {
            $module.Warn("The type of client setting '$name' cannot be changed after creation. " +
                "Current type is '$current_type'; ignoring requested type '$type'.")
        }

        $needs_desc_update = $null -ne $description -and $description -ne $client_setting.Description
        $current_priority = [int]$client_setting.Priority
        $needs_priority_update = $null -ne $priority -and $priority -ne $current_priority

        $cds_param = if ($device_omitted) { @() } elseif ($custom_device_settings.Count -eq 0) { $null } else { $custom_device_settings }
        $cus_param = if ($user_omitted) { @() } elseif ($custom_user_settings.Count -eq 0) { $null } else { $custom_user_settings }

        $custom_changed = $false
        if (-not $device_omitted -or -not $user_omitted) {
            try {
                $custom_changed = Set-CustomSetting -name $name -type $current_type `
                    -custom_device_settings $cds_param `
                    -custom_user_settings $cus_param `
                    -check_mode $module.CheckMode
            }
            catch {
                $module.FailJson("Failed to update custom settings for client setting '$name': $($_.Exception.Message)", $_)
            }
        }

        if ($needs_desc_update -or $needs_priority_update -or $custom_changed) {
            $module.result.changed = $true

            if ($needs_desc_update) {
                try {
                    $null = Set-CMClientSettingGeneral -Name $name -Description $description -WhatIf:$module.CheckMode
                }
                catch {
                    $module.FailJson("Failed to update description for client setting '$name': $($_.Exception.Message)", $_)
                }
            }

            if ($needs_priority_update -and -not $module.CheckMode) {
                try {
                    Set-ClientSettingPriority -name $name -priority $priority
                }
                catch {
                    $module.FailJson("Failed to update priority for client setting '$name': $($_.Exception.Message)", $_)
                }
            }
        }

        if (-not $module.CheckMode) {
            $client_setting = Get-CMClientSetting -Name $name
        }
        $module.result.client_setting = Format-ClientSettingResult -setting $client_setting
    }
}

$module.ExitJson()

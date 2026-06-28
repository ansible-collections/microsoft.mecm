#!powershell

# Copyright: (c) 2025, Ansible Project
# GNU General Public License v3.0+ (see COPYING or https://www.gnu.org/licenses/gpl-3.0.txt)

#AnsibleRequires -CSharpUtil Ansible.Basic
#AnsibleRequires -PowerShell ..module_utils._CMPsSetupUtils
#AnsibleRequires -PowerShell ..module_utils._ClientSettingUtils


$spec = @{
    options = @{
        site_code = @{ type = 'str'; required = $true }
        name = @{ type = 'str'; required = $false }
    }
    supports_check_mode = $true
}

$module = [Ansible.Basic.AnsibleModule]::Create($args, $spec)
$module.result.changed = $false

$site_code = $module.Params.site_code
$name = $module.Params.name

Import-CMPsModule -module $module
Test-CMSiteNameAndConnect -module $module -SiteCode $site_code

try {
    if ($null -ne $name -and $name -ne '') {
        $all_settings = @(Get-CMClientSetting -Name $name -ErrorAction Stop)
    }
    else {
        $all_settings = @(Get-CMClientSetting -ErrorAction Stop)
    }
}
catch {
    $module.FailJson("Failed to retrieve client settings: $($_.Exception.Message)", $_)
}

$results = @()
foreach ($setting in $all_settings) {
    $results += Format-ClientSettingResult -setting $setting
}

$module.result.client_settings = $results
$module.ExitJson()

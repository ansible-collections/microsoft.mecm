#!powershell

# Copyright: (c) 2025, Ansible Project
# GNU General Public License v3.0+ (see COPYING or https://www.gnu.org/licenses/gpl-3.0.txt)

#AnsibleRequires -CSharpUtil Ansible.Basic
#AnsibleRequires -PowerShell ..module_utils._CMPsSetupUtils


function Format-DeploymentTypeInfo {
    param (
        [Parameter(Mandatory = $true)][object]$module,
        [Parameter(Mandatory = $true)][object]$dt
    )
    $content_location = $null
    $install_command = $null

    try {
        [xml]$xml = $dt.SDMPackageXML
        $dtNode = $xml.AppMgmtDigest.DeploymentType
        if ($dtNode -is [array]) {
            $dt_name = $dt.LocalizedDisplayName
            foreach ($node in $dtNode) {
                if ($node.Title.'#text' -eq $dt_name -or $node.Title -eq $dt_name) {
                    $installer = $node.Installer
                    break
                }
            }
            if ($null -eq $installer) {
                $installer = $dtNode[0].Installer
            }
        }
        else {
            $installer = $dtNode.Installer
        }

        if ($null -ne $installer) {
            $content_location = $installer.Contents.Content.Location
            $install_command = $installer.CustomData.InstallCommandLine
        }
    }
    catch {
        $module.FailJson("Failed to parse deployment type XML metadata: $($_.Exception.Message)", $_)
    }

    return @{
        name = $dt.LocalizedDisplayName
        id = $dt.CI_ID.ToString()
        technology = $dt.Technology
        content_location = $content_location
        install_command = $install_command
    }
}


$spec = @{
    options = @{
        site_code = @{ type = 'str'; required = $true }
        application_name = @{ type = 'str'; required = $true }
        deployment_type_name = @{ type = 'str'; required = $false }
    }
    supports_check_mode = $true
}

$module = [Ansible.Basic.AnsibleModule]::Create($args, $spec)
$module.result.deployment_types = @()
$module.result.changed = $false

$site_code = $module.Params.site_code
$application_name = $module.Params.application_name

Import-CMPsModule -module $module
Test-CMSiteNameAndConnect -SiteCode $site_code -Module $module

$application = Get-CMApplication -Name $application_name
if ($null -eq $application) {
    $module.Warn("Application '$application_name' does not exist.")
    $module.ExitJson()
}

$results = [System.Collections.ArrayList]@()

if (-not [string]::IsNullOrEmpty($module.Params.deployment_type_name)) {
    try {
        $dt = Get-CMDeploymentType -ApplicationName $application_name `
            -DeploymentTypeName $module.Params.deployment_type_name `
            -ErrorAction SilentlyContinue
        if ($null -ne $dt) {
            $results.Add((Format-DeploymentTypeInfo -module $module -dt $dt)) | Out-Null
        }
    }
    catch {
        $module.FailJson(
            "Failed to query deployment type '$($module.Params.deployment_type_name)' " +
            "for application '$application_name': $($_.Exception.Message)", $_
        )
    }
}
else {
    try {
        $all_dts = @(Get-CMDeploymentType -ApplicationName $application_name -ErrorAction SilentlyContinue)
        foreach ($dt in $all_dts) {
            if ($null -eq $dt) { continue }
            $results.Add((Format-DeploymentTypeInfo -module $module -dt $dt)) | Out-Null
        }
    }
    catch {
        $module.FailJson(
            "Failed to query deployment types for application '$application_name': $($_.Exception.Message)", $_
        )
    }
}

$module.result.deployment_types = @($results)

$module.ExitJson()

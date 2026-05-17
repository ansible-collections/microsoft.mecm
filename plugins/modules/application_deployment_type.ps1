#!powershell

# Copyright: (c) 2025, Ansible Project
# GNU General Public License v3.0+ (see COPYING or https://www.gnu.org/licenses/gpl-3.0.txt)

#AnsibleRequires -CSharpUtil Ansible.Basic
#AnsibleRequires -PowerShell ..module_utils._CMPsSetupUtils


$GET_DT_PARAMS = @{
    content_location = { param($dt, $installer) $installer.Contents.Content.Location }
    install_command = { param($dt, $installer) $installer.CustomData.InstallCommandLine }
}


$PATH_PARAMS = @('content_location')


function Test-ContentLocationMatch {
    param (
        [Parameter(Mandatory = $true)][AllowEmptyString()][AllowNull()][string]$stored,
        [Parameter(Mandatory = $true)][AllowEmptyString()][AllowNull()][string]$provided
    )
    if ([string]::IsNullOrEmpty($stored) -or [string]::IsNullOrEmpty($provided)) {
        return $false
    }

    $normalizedStored = $stored.TrimEnd('\', '/').ToLower()
    $normalizedProvided = $provided.TrimEnd('\', '/').ToLower()

    if ($normalizedStored -eq $normalizedProvided) {
        return $true
    }

    $providedDir = Split-Path -Path $normalizedProvided -Parent
    if (-not [string]::IsNullOrEmpty($providedDir)) {
        if ($normalizedStored -eq $providedDir.TrimEnd('\', '/').ToLower()) {
            return $true
        }
    }

    return $false
}


function Get-DeploymentTypeInstaller {
    param (
        [Parameter(Mandatory = $true)][object]$module,
        [Parameter(Mandatory = $true)][object]$dt
    )
    try {
        [xml]$xml = $dt.SDMPackageXML
    }
    catch {
        $module.FailJson("Failed to parse deployment type XML metadata: $($_.Exception.Message)", $_)
    }

    $dtNode = $xml.AppMgmtDigest.DeploymentType
    if ($dtNode -is [array]) {
        $dt_name = $dt.LocalizedDisplayName
        foreach ($node in $dtNode) {
            if ($node.Title.'#text' -eq $dt_name -or $node.Title -eq $dt_name) {
                return $node.Installer
            }
        }
        return $dtNode[0].Installer
    }
    return $dtNode.Installer
}


function Test-DeploymentTypeNeedsUpdate {
    param (
        [Parameter(Mandatory = $true)][object]$module,
        [Parameter(Mandatory = $true)][object]$dt,
        [Parameter(Mandatory = $true)][string]$type
    )
    $installer = Get-DeploymentTypeInstaller -module $module -dt $dt

    foreach ($key in $GET_DT_PARAMS.Keys) {
        if ($null -eq $module.Params.$key) { continue }
        if ([string]::IsNullOrEmpty($module.Params.$key)) { continue }

        $current_value = & $GET_DT_PARAMS[$key] $dt $installer

        if ($key -in $PATH_PARAMS) {
            if (-not (Test-ContentLocationMatch -stored $current_value -provided $module.Params.$key)) {
                return $true
            }
        }
        elseif ($module.Params.$key -ne $current_value) {
            return $true
        }
    }

    return $false
}


function Format-DeploymentTypeResult {
    param (
        [Parameter(Mandatory = $true)][object]$dt
    )
    return @{
        name = $dt.LocalizedDisplayName
        id = $dt.CI_ID.ToString()
        technology = $dt.Technology
    }
}


$spec = @{
    options = @{
        site_code = @{ type = 'str'; required = $true }
        application_name = @{ type = 'str'; required = $true }
        deployment_type_name = @{ type = 'str'; required = $true }
        type = @{ type = 'str'; required = $true; choices = @('msi', 'script') }
        state = @{ type = 'str'; required = $false; default = 'present'; choices = @('present', 'absent') }
        content_location = @{ type = 'str'; required = $false }
        install_command = @{ type = 'str'; required = $false }
        script_language = @{ type = 'str'; required = $false; choices = @('PowerShell', 'VBScript', 'JavaScript') }
        script_file = @{ type = 'str'; required = $false }
    }
    required_if = @(
        , @('type', 'msi', @('content_location'))
        , @('type', 'script', @('install_command', 'script_language', 'script_file'))
    )
    supports_check_mode = $true
}

$module = [Ansible.Basic.AnsibleModule]::Create($args, $spec)
$module.result.changed = $false
$module.result.deployment_type = @{}

$site_code = $module.Params.site_code
$state = $module.Params.state
$application_name = $module.Params.application_name
$deployment_type_name = $module.Params.deployment_type_name
$type = $module.Params.type

Import-CMPsModule -module $module
Test-CMSiteNameAndConnect -module $module -SiteCode $site_code

$application = Get-CMApplication -Name $application_name
if ($null -eq $application) {
    $module.FailJson("Application '$application_name' does not exist.")
}

$existing_dt = Get-CMDeploymentType -ApplicationName $application_name `
    -DeploymentTypeName $deployment_type_name -ErrorAction SilentlyContinue

if (($state -eq 'absent') -and ($null -ne $existing_dt)) {
    $module.result.changed = $true
    $module.result.deployment_type = Format-DeploymentTypeResult -dt $existing_dt
    if (-not $module.CheckMode) {
        try {
            Remove-CMDeploymentType -InputObject $existing_dt -Force -Confirm:$false
        }
        catch {
            $module.FailJson("Failed to remove deployment type: $($_.Exception.Message)", $_)
        }
    }
}
elseif ($state -eq 'present') {
    if ($null -ne $existing_dt) {
        $needs_update = Test-DeploymentTypeNeedsUpdate -module $module -dt $existing_dt -type $type
        $module.result.changed = $needs_update

        if ($needs_update) {
            try {
                if ($type -eq 'msi') {
                    Set-CMMsiDeploymentType `
                        -ApplicationName $application_name `
                        -DeploymentTypeName $deployment_type_name `
                        -ContentLocation $module.Params.content_location `
                        -Confirm:$false -WhatIf:$module.CheckMode
                }
                elseif ($type -eq 'script') {
                    $set_params = @{
                        ApplicationName = $application_name
                        DeploymentTypeName = $deployment_type_name
                        InstallCommand = $module.Params.install_command
                        ScriptLanguage = $module.Params.script_language
                        ScriptFile = $module.Params.script_file
                    }
                    if (-not [string]::IsNullOrEmpty($module.Params.content_location)) {
                        $set_params.ContentLocation = $module.Params.content_location
                    }
                    Set-CMScriptDeploymentType @set_params -Confirm:$false -WhatIf:$module.CheckMode
                }
                if (-not $module.CheckMode) {
                    $existing_dt = Get-CMDeploymentType -ApplicationName $application_name `
                        -DeploymentTypeName $deployment_type_name -ErrorAction SilentlyContinue
                }
            }
            catch {
                $module.FailJson("Failed to update deployment type: $($_.Exception.Message)", $_)
            }
        }

        $module.result.deployment_type = Format-DeploymentTypeResult -dt $existing_dt
    }
    else {
        $module.result.changed = $true
        try {
            if ($type -eq 'msi') {
                $new_dt = Add-CMMsiDeploymentType `
                    -ApplicationName $application_name `
                    -DeploymentTypeName $deployment_type_name `
                    -ContentLocation $module.Params.content_location `
                    -Force -WhatIf:$module.CheckMode
            }
            elseif ($type -eq 'script') {
                $script_params = @{
                    ApplicationName = $application_name
                    DeploymentTypeName = $deployment_type_name
                    InstallCommand = $module.Params.install_command
                    ScriptLanguage = $module.Params.script_language
                    ScriptFile = $module.Params.script_file
                }
                if (-not [string]::IsNullOrEmpty($module.Params.content_location)) {
                    $script_params.ContentLocation = $module.Params.content_location
                }
                $new_dt = Add-CMScriptDeploymentType @script_params -WhatIf:$module.CheckMode
            }
            if ($module.CheckMode) {
                $module.result.deployment_type = @{
                    name = $deployment_type_name
                    id = 'check_mode'
                    technology = $type
                }
            }
            else {
                $module.result.deployment_type = Format-DeploymentTypeResult -dt $new_dt
            }
        }
        catch {
            $module.FailJson("Failed to add deployment type: $($_.Exception.Message)", $_)
        }
    }
}

$module.ExitJson()

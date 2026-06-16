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


function Get-CurrentRunType {
    <#
    .SYNOPSIS
    Derives the effective run_type string from the stored ADR properties.
    #>
    param (
        [Parameter(Mandatory = $true)][object]$adr
    )

    $align_with_sync = $null
    if (-not [string]::IsNullOrEmpty($adr.AutoDeploymentProperties)) {
        try {
            [xml]$xml = $adr.AutoDeploymentProperties
            $align_with_sync = $xml.AutoDeploymentRule.AlignWithSyncSchedule
        }
        catch {
            $null = $_
        }
    }

    if ($align_with_sync -eq 'true') {
        return 'RunTheRuleAfterAnySoftwareUpdatePointSynchronization'
    }

    if (-not [string]::IsNullOrEmpty($adr.Schedule)) {
        return 'RunTheRuleOnSchedule'
    }

    return 'DoNotRunThisRuleAutomatically'
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


$spec = @{
    options = @{
        site_code = @{ type = 'str'; required = $true }
        name = @{ type = 'str'; required = $false }
    }
    supports_check_mode = $true
}

$module = [Ansible.Basic.AnsibleModule]::Create($args, $spec)
$module.result.changed = $false
$module.result.software_update_adrs = @()

$site_code = $module.Params.site_code
$name = $module.Params.name

Import-CMPsModule -module $module
Test-CMSiteNameAndConnect -module $module -SiteCode $site_code

$cmdlet_params = @{}
if (-not [string]::IsNullOrEmpty($name)) {
    $cmdlet_params['Name'] = $name
}

try {
    $adrs = Get-CMSoftwareUpdateAutoDeploymentRule @cmdlet_params
}
catch {
    $module.FailJson("Failed to retrieve Software Update ADRs: $($_.Exception.Message)", $_)
}

if ($null -eq $adrs) {
    if (-not [string]::IsNullOrEmpty($name)) {
        $module.Warn("Software Update ADR '$name' was not found.")
    }
    $module.ExitJson()
}

$adrs_formatted = @($adrs | ForEach-Object { Format-ADRResult -adr $_ })
$module.result.software_update_adrs = $adrs_formatted

$module.ExitJson()

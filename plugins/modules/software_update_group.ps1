#!powershell

# Copyright: (c) 2025, Ansible Project
# GNU General Public License v3.0+ (see COPYING or https://www.gnu.org/licenses/gpl-3.0.txt)

#AnsibleRequires -CSharpUtil Ansible.Basic
#AnsibleRequires -PowerShell ..module_utils._CMPsSetupUtils
#AnsibleRequires -PowerShell ..module_utils._GetObjectUtils


function Complete-SUGCreation {
    # Create a new software update group
    param (
        [Parameter(Mandatory = $true)][object]$module,
        [Parameter(Mandatory = $true)][array]$updates
    )
    $module.result.changed = $true
    if (-not $module.CheckMode) {
        # Map module parameters to cmdlet arguments
        $cmdlet_params = Format-ModuleParamAsCmdletArgument `
            -module $module -direct_mapped_params @{
            name = "Name"
            description = "Description"
        } -datetime_params @{} -switch_params @{}
        $cmdlet_params['InputObject'] = $updates
        try {
            $newSug = New-CMSoftwareUpdateGroup @cmdlet_params
            $module.result.software_update_group = @{
                name = $newSug.LocalizedDisplayName
                id = $newSug.CI_ID.ToString()
            }
        }
        catch {
            $module.FailJson("Failed to create software update group: $($_.Exception.Message)", $_)
        }
    }
}


function Test-SoftwareUpdateGroupNeedsUpdate {
    # Test if the software update group needs to be updated
    param (
        [Parameter(Mandatory = $true)][object]$module,
        [Parameter(Mandatory = $true)][object]$sug,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][array]$updates
    )
    if (($null -ne $module.Params.name) -and ($module.Params.name -ne $sug.LocalizedDisplayName)) {
        return $true
    }
    if (($null -ne $module.Params.description) -and ($module.Params.description -ne $sug.LocalizedDescription)) {
        return $true
    }
    if (($module.Params.clear_expired_updates) -and ($sug.ContainsExpiredUpdates)) {
        return $true
    }
    if (($module.Params.clear_superseded_updates) -and ($sug.ContainsSupersededUpdates)) {
        return $true
    }

    foreach ($update in $updates) {
        if (-not $sug.Updates.Contains($update.CI_ID)) {
            return $true
        }
    }

    return $false
}


function Complete-SUGRemoval {
    # Remove the software update group
    param (
        [Parameter(Mandatory = $true)][object]$module,
        [Parameter(Mandatory = $true)][object]$sug
    )
    $module.result.changed = $true
    if (-not $module.CheckMode) {
        try {
            Remove-CMSoftwareUpdateGroup -InputObject $sug -Force
        }
        catch {
            $module.FailJson("Failed to remove software update group: $($_.Exception.Message)", $_)
        }
    }
    $module.result.software_update_group = @{
        name = $sug.LocalizedDisplayName
        id = $sug.CI_ID.ToString()
    }
}


function Complete-SUGUpdate {
    # Update the software update group
    param (
        [Parameter(Mandatory = $true)][object]$module,
        [Parameter(Mandatory = $true)][object]$sug,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][array]$updates
    )
    # Test if the software update group needs to be updated
    $needs_update = Test-SoftwareUpdateGroupNeedsUpdate `
        -module $module `
        -sug $sug `
        -updates $updates
    $module.result.changed = $needs_update

    # Update the software update group if it needs to be updated
    if (($needs_update) -and (-not $module.CheckMode)) {
        $cmdlet_params = Format-ModuleParamAsCmdletArgument `
            -module $module -direct_mapped_params @{
            name = "NewName"
            description = "Description"
        } -switch_params @{
            clear_expired_updates = "ClearExpiredUpdates"
            clear_superseded_updates = "ClearSupersededUpdates"
        } -datetime_params @{}

        $updates_to_add = $updates | Where-Object { -not $sug.Updates.Contains($_.CI_ID.ToString()) }
        if ($null -eq $updates_to_add) {
            $updates_to_add = @()
        }
        $cmdlet_params.Add("AddSoftwareUpdate", $updates_to_add)

        try {
            Set-CMSoftwareUpdateGroup @cmdlet_params -InputObject $sug
        }
        catch {
            $module.FailJson("Failed to update software update group: $($_.Exception.Message)", $_)
        }
    }
    $module.result.software_update_group = @{
        name = $sug.LocalizedDisplayName
        id = $sug.CI_ID.ToString()
    }
}


$spec = @{
    options = @{
        site_code = @{ type = 'str'; required = $true }
        name = @{ type = 'str'; required = $false }
        id = @{ type = 'str'; required = $false }
        description = @{ type = 'str'; required = $false }
        state = @{ type = 'str'; required = $false; default = "present"; choices = @("present", "absent") }
        software_update_ids = @{ type = 'list'; required = $false; elements = 'str' }
        software_update_names = @{ type = 'list'; required = $false; elements = 'str' }
        clear_expired_updates = @{ type = 'bool'; required = $false; default = $false }
        clear_superseded_updates = @{ type = 'bool'; required = $false; default = $false }
    }
    required_one_of = @(
        , @("name", "id")
    )
    supports_check_mode = $true
}


$module = [Ansible.Basic.AnsibleModule]::Create($args, $spec)
$module.result.changed = $false
$module.result.software_update_group = @{}

# Map frequently used module parameters to cmdlet arguments
$site_code = $module.Params.site_code
$state = $module.Params.state
$name = $module.Params.name
$id = $module.Params.id

# Setup PS environment
Import-CMPsModule -module $module
Test-CMSiteNameAndConnect -module $module -SiteCode $site_code

# Check if the software update group exists
$software_update_group = Get-SoftwareUpdateGroupObject `
    -module $module `
    -software_update_group_name $name `
    -software_update_group_id $id `
    -throw_error_if_not_found $false

# Route to the appropriate function based on the software update group existence
if (($state -eq "absent") -and ($null -ne $software_update_group)) {
    Complete-SUGRemoval -module $module -sug $software_update_group
}
elseif ($state -eq "present") {
    $updates = @(
        if ($null -ne $module.Params.software_update_ids) {
            $module.Params.software_update_ids | ForEach-Object {
                Get-SoftwareUpdateObject -module $module -software_update_id $_ -throw_error_if_not_found $true
            }
        }
        if ($null -ne $module.Params.software_update_names) {
            $module.Params.software_update_names | ForEach-Object {
                Get-SoftwareUpdateObject -module $module -software_update_name $_ -throw_error_if_not_found $true
            }
        }
    )

    if ($null -ne $software_update_group) {
        Complete-SUGUpdate -module $module -sug $software_update_group -updates $updates
    }
    else {
        if ($null -eq $module.Params.name) {
            $module.FailJson("The name parameter is required when creating a new software update group.")
        }
        if ($updates.Count -eq 0) {
            $module.FailJson("Either the software_update_ids or software_update_names parameter is required when creating a new software update group.")
        }
        Complete-SUGCreation -module $module -updates $updates
    }

}


$module.ExitJson()

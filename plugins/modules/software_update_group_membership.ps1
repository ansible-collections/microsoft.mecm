#!powershell

# Copyright: (c) 2025, Ansible Project
# GNU General Public License v3.0+ (see COPYING or https://www.gnu.org/licenses/gpl-3.0.txt)

#AnsibleRequires -CSharpUtil Ansible.Basic
#AnsibleRequires -PowerShell ..module_utils._CMPsSetupUtils
#AnsibleRequires -PowerShell ..module_utils._GetObjectUtils


function Get-SoftwareUpdatesForMembership {
    param (
        [Parameter(Mandatory = $true)][object]$module,
        [Parameter(Mandatory = $true)][string]$state
    )
    if ($state -eq "absent") {
        $fail_if_not_found = $false
    }
    else {
        $fail_if_not_found = $true
    }

    $updates = @(
        if ($null -ne $module.Params.software_update_ids) {
            $module.Params.software_update_ids | ForEach-Object {
                Get-SoftwareUpdateObject -module $module -software_update_id $_ -throw_error_if_not_found $fail_if_not_found
            }
        }
        if ($null -ne $module.Params.software_update_names) {
            $module.Params.software_update_names | ForEach-Object {
                Get-SoftwareUpdateObject -module $module -software_update_name $_ -throw_error_if_not_found $fail_if_not_found
            }
        }
    )
    return $updates
}


function Complete-SURemoval {
    # Remove the software updates from the software update group
    param (
        [Parameter(Mandatory = $true)][object]$module,
        [Parameter(Mandatory = $true)][object]$sug,
        [Parameter(Mandatory = $true)][array]$updates_from_params
    )
    $updates_to_remove = $updates_from_params | Where-Object { $sug.Updates.Contains($_.CI_ID) }
    if (($updates_to_remove.Count -eq 0) -or ($null -eq $updates_to_remove)) {
        return
    }

    $module.result.changed = $true
    if (-not $module.CheckMode) {
        try {
            Set-CMSoftwareUpdateGroup -InputObject $sug -RemoveSoftwareUpdate $updates_to_remove -Force
        }
        catch {
            $module.FailJson("Failed to remove software updates from software update group: $($_.Exception.Message)", $_)
        }
    }
}


function Complete-SUPresent {
    # Add the software updates to the software update group
    param (
        [Parameter(Mandatory = $true)][object]$module,
        [Parameter(Mandatory = $true)][object]$sug,
        [Parameter(Mandatory = $true)][array]$updates_from_params
    )
    $updates_to_add = $updates_from_params | Where-Object { -not $sug.Updates.Contains($_.CI_ID) }
    if (($null -eq $updates_to_add) -or ($updates_to_add.Count -eq 0)) {
        return
    }

    $module.result.changed = $true
    if (-not $module.CheckMode) {
        try {
            Set-CMSoftwareUpdateGroup -InputObject $sug -AddSoftwareUpdate $updates_to_add
        }
        catch {
            $module.FailJson("Failed to add software updates to software update group: $($_.Exception.Message)", $_)
        }
    }
}


function Complete-SUSet {
    # Set the absolute list of software updates in the software update group
    param (
        [Parameter(Mandatory = $true)][object]$module,
        [Parameter(Mandatory = $true)][object]$sug,
        [Parameter(Mandatory = $true)][array]$updates_from_params
    )
    $final_update_ids = $updates_from_params | ForEach-Object { $_.CI_ID }
    if ($null -eq $final_update_ids) {
        $final_update_ids = @()
    }

    $updates_to_add = $updates_from_params | Where-Object { -not $sug.Updates.Contains($_.CI_ID) }
    if ($null -eq $updates_to_add) {
        $updates_to_add = @()
    }

    $update_ids_to_remove = $sug.Updates | Where-Object { $final_update_ids -notcontains $_ }
    if ($null -eq $update_ids_to_remove) {
        $update_ids_to_remove = @()
    }
    $updates_to_remove = $update_ids_to_remove | ForEach-Object {
        Get-SoftwareUpdateObject -module $module -software_update_id $_ -throw_error_if_not_found $false
    }
    if ($null -eq $updates_to_remove) {
        $updates_to_remove = @()
    }

    # set the final list of updates in the group. First add the updates that need to be added,
    # then remove the updates that need to be removed so theres always at least one update in the group
    if (($updates_to_add.Count -gt 0) -or ($updates_to_remove.Count -gt 0)) {
        $module.result.changed = $true
        if (-not $module.CheckMode) {
            try {
                Set-CMSoftwareUpdateGroup -InputObject $sug -AddSoftwareUpdate $updates_to_add -RemoveSoftwareUpdate $updates_to_remove
            }
            catch {
                $module.FailJson("Failed to set software updates in software update group: $($_.Exception.Message)", $_)
            }
        }
    }
}


$spec = @{
    options = @{
        site_code = @{ type = 'str'; required = $true }
        group_name = @{ type = 'str'; required = $false }
        group_id = @{ type = 'str'; required = $false }
        state = @{ type = 'str'; required = $false; default = "present"; choices = @("present", "absent", "set") }
        software_update_ids = @{ type = 'list'; required = $false; elements = 'str' }
        software_update_names = @{ type = 'list'; required = $false; elements = 'str' }
    }
    required_one_of = @(
        , @("group_name", "group_id")
    )
    supports_check_mode = $true
}


$module = [Ansible.Basic.AnsibleModule]::Create($args, $spec)
$module.result.changed = $false

# Map frequently used module parameters to cmdlet arguments
$site_code = $module.Params.site_code
$state = $module.Params.state
$group_name = $module.Params.group_name
$group_id = $module.Params.group_id

# Setup PS environment
Import-CMPsModule -module $module
Test-CMSiteNameAndConnect -module $module -SiteCode $site_code

# Get the software update group
$sug = Get-SoftwareUpdateGroupObject `
    -module $module `
    -software_update_group_name $group_name `
    -software_update_group_id $group_id `
    -throw_error_if_not_found $true

$updates_from_params = Get-SoftwareUpdatesForMembership -module $module -state $state

# Route to the appropriate function based on the software update group existence
if ($state -eq "absent") {
    if ($updates_from_params.Count -gt 0) {
        Complete-SURemoval -module $module -sug $sug -updates_from_params $updates_from_params
    }
}
elseif ($state -eq "present") {
    Complete-SUPresent -module $module -sug $sug -updates_from_params $updates_from_params
}
elseif ($state -eq "set") {
    Complete-SUSet -module $module -sug $sug -updates_from_params $updates_from_params
}

$module.result.software_update_group = @{
    name = $sug.LocalizedDisplayName
    id = $sug.CI_ID.ToString()
    updates = $sug.Updates
}

$module.ExitJson()

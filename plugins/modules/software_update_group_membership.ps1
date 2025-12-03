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

    $updates = @()
    foreach ($update_id in $module.Params.software_update_ids) {
        $updates += Get-SoftwareUpdateObject -module $module -software_update_id $update_id -throw_error_if_not_found $fail_if_not_found
    }
    foreach ($update_name in $module.Params.software_update_names) {
        $updates += Get-SoftwareUpdateObject -module $module -software_update_name $update_name -throw_error_if_not_found $fail_if_not_found
    }
    return $updates
}


function Complete-SURemoval {
    # Remove the software updates from the software update group
    param (
        [Parameter(Mandatory = $true)][object]$module,
        [Parameter(Mandatory = $true)][object]$sug,
        [Parameter(Mandatory = $true)][array]$updates
    )
    $updates_to_remove = @()
    foreach ($update in $updates) {
        if ($sug.Updates.Contains($update.CI_ID)) {
            $updates_to_remove += $update
        }
    }

    if ($updates_to_remove.Count -eq 0) {
        return
    }

    $module.result.changed = $true
    if (-not $module.CheckMode) {
        try {
            Set-CMSoftwareUpdateGroup -InputObject $sug -RemoveSoftwareUpdate $updates -Force
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
        [Parameter(Mandatory = $true)][array]$updates
    )
    $updates_to_add = @()
    foreach ($update in $updates) {
        if (-not $sug.Updates.Contains($update.CI_ID)) {
            $updates_to_add += $update
        }
    }

    if ($updates_to_add.Count -eq 0) {
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
        [Parameter(Mandatory = $true)][array]$updates
    )
    $updates_to_add = @()
    $updates_to_remove = @()
    $final_update_ids = @()

    #figure out which updates need to be added, and track the IDs for updates that should be in the final list
    foreach ($update in $updates) {
        if (-not $sug.Updates.Contains($update.CI_ID)) {
            $updates_to_add += $update
        }
        $final_update_ids += $update.CI_ID
    }

    # figure out which updates need to be removed
    foreach ($update_id in $sug.Updates) {
        if (-not $final_update_ids.Contains($update_id)) {
            $updates_to_remove += Get-SoftwareUpdateObject `
                -module $module `
                -software_update_id $update_id
        }
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
Test-CMSiteNameAndConnect -module $module -site_code $site_code

# Get the software update group
$sug = Get-SoftwareUpdateGroupObject `
    -module $module `
    -software_update_group_name $group_name `
    -software_update_group_id $group_id `
    -throw_error_if_not_found $true

$updates = Get-SoftwareUpdatesForMembership -module $module -state $state

# Route to the appropriate function based on the software update group existence
if ($state -eq "absent") {
    if ($updates.Count -gt 0) {
        Complete-SURemoval -module $module -sug $sug -updates $updates
    }
}
elseif ($state -eq "present") {
    Complete-SUPresent -module $module -sug $sug -updates $updates
}
elseif ($state -eq "set") {
    Complete-SUSet -module $module -sug $sug -updates $updates
}

$module.result.software_update_group = @{
    name = $sug.LocalizedDisplayName
    id = $sug.CI_ID.ToString()
    updates = $sug.Updates
}

$module.ExitJson()

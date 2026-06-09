#!powershell

# Copyright: (c) 2025, Ansible Project
# GNU General Public License v3.0+ (see COPYING or https://www.gnu.org/licenses/gpl-3.0.txt)

#AnsibleRequires -CSharpUtil Ansible.Basic
#AnsibleRequires -PowerShell ..module_utils._CMPsSetupUtils


function Get-DPNamesForGroup {
    param ([Parameter(Mandatory = $true)][string]$groupName)
    $names = [System.Collections.Generic.List[string]]::new()
    $dps = Get-CMDistributionPoint -DistributionPointGroupName $groupName -ErrorAction SilentlyContinue
    if ($null -ne $dps) {
        foreach ($dp in @($dps)) {
            if ($dp.NetworkOSPath) {
                $names.Add(($dp.NetworkOSPath -replace '^\\\\', ''))
            }
        }
    }
    return , [string[]]$names.ToArray()
}


function Format-DPGroupResult {
    param (
        [Parameter(Mandatory = $true)][object]$group,
        [AllowEmptyCollection()][string[]]$dpNames = @()
    )
    return @{
        name = $group.Name
        id = $group.GroupID.ToString()
        description = $group.Description
        distribution_points = @($dpNames)
    }
}


$spec = @{
    options = @{
        site_code = @{ type = 'str'; required = $true }
        name = @{ type = 'str'; required = $true }
        new_name = @{ type = 'str'; required = $false }
        description = @{ type = 'str'; required = $false }
        distribution_points = @{ type = 'list'; elements = 'str'; required = $false }
        state = @{ type = 'str'; required = $false; default = 'present'; choices = @('present', 'absent') }
    }
    supports_check_mode = $true
}

$module = [Ansible.Basic.AnsibleModule]::Create($args, $spec)
$module.result.changed = $false
$module.result.distribution_point_group = @{}

$site_code = $module.Params.site_code
$name = $module.Params.name
$new_name = $module.Params.new_name
$description = $module.Params.description
$desired_dps = $module.Params.distribution_points
$state = $module.Params.state

Import-CMPsModule -module $module
Test-CMSiteNameAndConnect -module $module -SiteCode $site_code

$existing_group = Get-CMDistributionPointGroup -Name $name -ErrorAction SilentlyContinue

if ($state -eq 'absent') {
    if ($null -ne $existing_group) {
        $module.result.changed = $true
        $current_dps = Get-DPNamesForGroup -groupName $name
        $module.result.distribution_point_group = Format-DPGroupResult -group $existing_group -dpNames $current_dps
        if (-not $module.CheckMode) {
            try {
                Remove-CMDistributionPointGroup -Name $name -Force -Confirm:$false
            }
            catch {
                $module.FailJson("Failed to remove DP group '$name': $($_.Exception.Message)", $_)
            }
        }
    }
}
elseif ($state -eq 'present') {
    if ($null -eq $existing_group) {
        if (-not [string]::IsNullOrEmpty($new_name)) {
            $module.FailJson("Cannot rename DP group to '$new_name' because no group exists with the original name '$name'.")
        }

        # --- Create new group ---
        $module.result.changed = $true
        $create_params = @{ Name = $name }
        if (-not [string]::IsNullOrEmpty($description)) {
            $create_params.Description = $description
        }
        try {
            New-CMDistributionPointGroup @create_params -WhatIf:$module.CheckMode
        }
        catch {
            $module.FailJson("Failed to create DP group '$name': $($_.Exception.Message)", $_)
        }

        if (-not $module.CheckMode -and $null -ne $desired_dps) {
            foreach ($dp in $desired_dps) {
                try {
                    Add-CMDistributionPointToGroup -DistributionPointName $dp `
                        -DistributionPointGroupName $name -ErrorAction Stop
                }
                catch {
                    $module.FailJson("Failed to add DP '$dp' to group '$name': $($_.Exception.Message)", $_)
                }
            }
            $new_group = Get-CMDistributionPointGroup -Name $name -ErrorAction SilentlyContinue
            $final_dps = Get-DPNamesForGroup -groupName $name
            $module.result.distribution_point_group = Format-DPGroupResult -group $new_group -dpNames $final_dps
        }
        else {
            $module.result.distribution_point_group = @{
                name = $name
                id = 'check_mode'
                description = if ($description) { $description } else { '' }
                distribution_points = @(if ($desired_dps) { $desired_dps } else { @() })
            }
        }
    }
    else {
        # --- Update existing group ---
        # The effective name after a potential rename
        $current_name = $name

        # Rename if new_name is requested and differs from current name
        if (-not [string]::IsNullOrEmpty($new_name) -and $new_name -ne $name) {
            $module.result.changed = $true
            try {
                Set-CMDistributionPointGroup -Name $name -NewName $new_name -Confirm:$false -WhatIf:$module.CheckMode
            }
            catch {
                $module.FailJson("Failed to rename DP group '$name' to '$new_name': $($_.Exception.Message)", $_)
            }
            $current_name = $new_name
        }

        # Update description if provided and differs
        if (-not [string]::IsNullOrEmpty($description) -and $description -ne $existing_group.Description) {
            $module.result.changed = $true
            try {
                Set-CMDistributionPointGroup -Name $current_name -Description $description `
                    -Confirm:$false -WhatIf:$module.CheckMode
            }
            catch {
                $module.FailJson("Failed to update description of DP group '$current_name': $($_.Exception.Message)", $_)
            }
        }

        # Reconcile distribution point membership
        if ($null -ne $desired_dps) {
            $current_dps = Get-DPNamesForGroup -groupName $current_name
            $current_dps_norm = @($current_dps | ForEach-Object { $_.ToLower() })
            $desired_dps_norm = @($desired_dps | ForEach-Object { $_.ToLower() })

            $to_add = @($desired_dps | Where-Object { $_.ToLower() -notin $current_dps_norm })
            $to_remove = @($current_dps | Where-Object { $_.ToLower() -notin $desired_dps_norm })

            if ($to_add.Count -gt 0 -or $to_remove.Count -gt 0) {
                $module.result.changed = $true
                if (-not $module.CheckMode) {
                    foreach ($dp in $to_add) {
                        try {
                            Add-CMDistributionPointToGroup -DistributionPointName $dp `
                                -DistributionPointGroupName $current_name -ErrorAction Stop
                        }
                        catch {
                            $module.FailJson("Failed to add DP '$dp' to group '$current_name': $($_.Exception.Message)", $_)
                        }
                    }
                    foreach ($dp in $to_remove) {
                        try {
                            Remove-CMDistributionPointFromGroup -DistributionPointName $dp `
                                -DistributionPointGroupName $current_name -Force -Confirm:$false -ErrorAction Stop
                        }
                        catch {
                            $module.FailJson("Failed to remove DP '$dp' from group '$current_name': $($_.Exception.Message)", $_)
                        }
                    }
                }
            }
        }

        if (-not $module.CheckMode) {
            $updated_group = Get-CMDistributionPointGroup -Name $current_name -ErrorAction SilentlyContinue
            $final_dps = Get-DPNamesForGroup -groupName $current_name
            $module.result.distribution_point_group = Format-DPGroupResult -group $updated_group -dpNames $final_dps
        }
        else {
            $predicted_dps = if ($null -ne $desired_dps) { $desired_dps } else { Get-DPNamesForGroup -groupName $name }
            $module.result.distribution_point_group = @{
                name = if ($new_name) { $new_name } else { $name }
                id = $existing_group.GroupID.ToString()
                description = if ($description) { $description } else { $existing_group.Description }
                distribution_points = @($predicted_dps)
            }
        }
    }
}

$module.ExitJson()

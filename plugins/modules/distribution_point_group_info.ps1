#!powershell

# Copyright: (c) 2025, Ansible Project
# GNU General Public License v3.0+ (see COPYING or https://www.gnu.org/licenses/gpl-3.0.txt)

#AnsibleRequires -CSharpUtil Ansible.Basic
#AnsibleRequires -PowerShell ..module_utils._CMPsSetupUtils


$spec = @{
    options = @{
        site_code = @{ type = 'str'; required = $true }
        name = @{ type = 'str'; required = $false }
    }
    supports_check_mode = $true
}

$module = [Ansible.Basic.AnsibleModule]::Create($args, $spec)
$module.result.distribution_point_groups = @()
$module.result.changed = $false

$site_code = $module.Params.site_code
$name = $module.Params.name

Import-CMPsModule -module $module
Test-CMSiteNameAndConnect -SiteCode $site_code -Module $module

# Fetch group(s)
if (-not [string]::IsNullOrEmpty($name)) {
    try {
        $groups = @(Get-CMDistributionPointGroup -Name $name -ErrorAction Stop)
    }
    catch {
        $module.FailJson("Failed to query DP group '$name': $($_.Exception.Message)", $_)
    }
    if (-not $groups) {
        $module.Warn("Distribution point group '$name' does not exist.")
        $module.ExitJson()
    }
}
else {
    try {
        $groups = @(Get-CMDistributionPointGroup -ErrorAction Stop)
    }
    catch {
        $module.FailJson("Failed to query distribution point groups: $($_.Exception.Message)", $_)
    }
}

foreach ($group in $groups) {
    if ($null -eq $group) { continue }

    try {
        $dps = @(Get-CMDistributionPoint -DistributionPointGroupName $group.Name -ErrorAction SilentlyContinue)
    }
    catch {
        $module.FailJson("Failed to query DPs for group '$($group.Name)': $($_.Exception.Message)", $_)
    }

    $dp_names = @()
    foreach ($dp in $dps) {
        if ($dp.NetworkOSPath) {
            $dp_names += $dp.NetworkOSPath -replace '^\\\\', ''
        }
    }

    $module.result.distribution_point_groups += @{
        name = $group.Name
        id = $group.GroupID.ToString()
        description = $group.Description
        member_count = $group.MemberCount
        distribution_points = @($dp_names)
    }
}

$module.ExitJson()

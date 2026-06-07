#!powershell

# Copyright: (c) 2025, Ansible Project
# GNU General Public License v3.0+ (see COPYING or https://www.gnu.org/licenses/gpl-3.0.txt)

#AnsibleRequires -CSharpUtil Ansible.Basic
#AnsibleRequires -PowerShell ..module_utils._CMPsSetupUtils


# Maps boundary type string names to the integer values stored in BoundaryType by Get-CMBoundary.
$BOUNDARY_TYPE_INT = @{
    IPSubnet = 0
    ADSite = 1
    IPV6Prefix = 2
    IPRange = 3
    Vpn = 4
}


function Format-BoundaryResult {
    param (
        [Parameter(Mandatory = $true)][object]$boundary
    )
    $type_int = [int]$boundary.BoundaryType
    $type_str = ($BOUNDARY_TYPE_INT.GetEnumerator() | Where-Object { $_.Value -eq $type_int } | Select-Object -First 1).Key

    return @{
        boundary_id = $boundary.BoundaryID.ToString()
        name = $boundary.DisplayName
        type = $type_str
        type_id = $type_int
        value = $boundary.Value
        group_count = [int]$boundary.GroupCount
    }
}


$spec = @{
    options = @{
        site_code = @{ type = 'str'; required = $true }
        name = @{ type = 'str'; required = $false }
        type = @{
            type = 'str'
            required = $false
            choices = @('IPSubnet', 'ADSite', 'IPV6Prefix', 'IPRange', 'Vpn')
        }
    }
    supports_check_mode = $true
}

$module = [Ansible.Basic.AnsibleModule]::Create($args, $spec)
$module.result.changed = $false

$site_code = $module.Params.site_code
$name = $module.Params.name
$type = $module.Params.type

Import-CMPsModule -module $module
Test-CMSiteNameAndConnect -module $module -SiteCode $site_code

try {
    if ($null -ne $name -and $name -ne '') {
        $all_boundaries = @(Get-CMBoundary -BoundaryName $name -ErrorAction Stop)
    }
    else {
        $all_boundaries = @(Get-CMBoundary -ErrorAction Stop)
    }
}
catch {
    $module.FailJson("Failed to retrieve boundaries: $($_.Exception.Message)", $_)
}

if ($null -ne $type -and $type -ne '') {
    $desired_type_int = $BOUNDARY_TYPE_INT[$type]
    $all_boundaries = @($all_boundaries | Where-Object { [int]$_.BoundaryType -eq $desired_type_int })
}

$results = @()
foreach ($boundary in $all_boundaries) {
    $results += Format-BoundaryResult -boundary $boundary
}

$module.result.boundaries = $results
$module.ExitJson()

#!powershell

# Copyright: (c) 2025, Ansible Project
# GNU General Public License v3.0+ (see COPYING or https://www.gnu.org/licenses/gpl-3.0.txt)

#AnsibleRequires -CSharpUtil Ansible.Basic
#AnsibleRequires -PowerShell ..module_utils._CMPsSetupUtils


# Maps boundary type string names (as accepted by New/Set-CMBoundary -Type) to the integer
# values stored in the BoundaryType property returned by Get-CMBoundary.
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


# Looks up a boundary by DisplayName (BoundaryName) first, then narrows the result
# by the unique type:value pair.  When no name is supplied an empty string is used,
# which returns boundaries that have no DisplayName set.
function Get-BoundaryByNameTypeAndValue {
    param (
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$search_name,
        [Parameter(Mandatory = $true)][int]$type_int,
        [Parameter(Mandatory = $true)][string]$value
    )
    if ($search_name -eq '') {
        $candidates = Get-CMBoundary -ErrorAction SilentlyContinue
    }
    else {
        $candidates = Get-CMBoundary -BoundaryName $search_name -ErrorAction SilentlyContinue
    }
    $found = $candidates |
        Where-Object { [int]$_.BoundaryType -eq $type_int -and $_.Value -eq $value } |
        Select-Object -First 1
    return $found
}


# Validates that when type is Vpn the value matches one of the accepted formats:
#   Auto:On
#   Name:<vpn_name>
#   Description:<vpn_description>
function Assert-VpnBoundaryValue {
    param (
        [Parameter(Mandatory = $true)][object]$module,
        [Parameter(Mandatory = $true)][string]$value
    )
    if ($value -eq 'Auto:On') { return }
    if ($value -match '^Name:.+') { return }
    if ($value -match '^Description:.+') { return }
    $module.FailJson(
        "Invalid value '$value' for type 'Vpn'. " +
        "Accepted formats: 'Auto:On', 'Name:<vpn_name>', 'Description:<vpn_description>'."
    )
}


$spec = @{
    options = @{
        site_code = @{ type = 'str'; required = $true }
        name = @{ type = 'str'; required = $false; default = '' }
        type = @{
            type = 'str'
            required = $true
            choices = @('IPSubnet', 'ADSite', 'IPV6Prefix', 'IPRange', 'Vpn')
        }
        value = @{ type = 'str'; required = $true }
        new_name = @{ type = 'str'; required = $false; default = '' }
        state = @{
            type = 'str'
            required = $false
            default = 'present'
            choices = @('present', 'absent')
        }
    }
    supports_check_mode = $true
}

$module = [Ansible.Basic.AnsibleModule]::Create($args, $spec)
$module.result.changed = $false
$module.result.boundary = @{}

$site_code = $module.Params.site_code
$name = $module.Params.name
$type = $module.Params.type
$value = $module.Params.value
$new_name = $module.Params.new_name
$state = $module.Params.state

if ($type -eq 'Vpn') {
    Assert-VpnBoundaryValue -module $module -value $value
}

Import-CMPsModule -module $module
Test-CMSiteNameAndConnect -module $module -SiteCode $site_code

$desired_type_int = $BOUNDARY_TYPE_INT[$type]
$boundary = Get-BoundaryByNameTypeAndValue -search_name $name -type_int $desired_type_int -value $value

if ($state -eq 'absent') {
    if ($null -ne $boundary) {
        try {
            Remove-CMBoundary -InputObject $boundary -Force -Confirm:$false -WhatIf:$module.CheckMode
        }
        catch {
            $module.FailJson("Failed to remove boundary (type='$type', value='$value'): $($_.Exception.Message)", $_)
        }
        $module.result.changed = $true
        $module.result.boundary = Format-BoundaryResult -boundary $boundary
    }
}
elseif ($state -eq 'present') {
    if ($null -eq $boundary) {
        $existing_by_type_value = Get-CMBoundary -ErrorAction SilentlyContinue |
            Where-Object { [int]$_.BoundaryType -eq $desired_type_int -and $_.Value -eq $value } |
            Select-Object -First 1

        if ($null -ne $existing_by_type_value) {
            $module.Warn(
                "A boundary with type='$type' and value='$value' already exists " +
                "under the name '$($existing_by_type_value.DisplayName)'. " +
                "No changes were made. To rename it, run the task again using " +
                "name='$($existing_by_type_value.DisplayName)' and new_name='<desired name>'."
            )
            $module.result.boundary = Format-BoundaryResult -boundary $existing_by_type_value
            $module.ExitJson()
        }

        $create_params = @{ Type = $type; Value = $value }
        if ($name -ne '') {
            $create_params['DisplayName'] = $name
        }
        try {
            $boundary = New-CMBoundary @create_params -WhatIf:$module.CheckMode
        }
        catch {
            $module.FailJson("Failed to create boundary (type='$type', value='$value'): $($_.Exception.Message)", $_)
        }
        $module.result.changed = $true
    }
    else {
        if ($new_name -ne '' -and $boundary.DisplayName -ne $new_name) {
            try {
                Set-CMBoundary -InputObject $boundary -NewName $new_name -Confirm:$false -WhatIf:$module.CheckMode
            }
            catch {
                $module.FailJson("Failed to rename boundary to '$new_name': $($_.Exception.Message)", $_)
            }
            $module.result.changed = $true

            if (-not $module.CheckMode) {
                $boundary = Get-BoundaryByNameTypeAndValue -search_name $new_name -type_int $desired_type_int -value $value
            }
        }
    }

    if (-not $module.CheckMode -and $null -ne $boundary) {
        $module.result.boundary = Format-BoundaryResult -boundary $boundary
    }
}

$module.ExitJson()

#!powershell

# Copyright: (c) 2025, Ansible Project
# GNU General Public License v3.0+ (see COPYING or https://www.gnu.org/licenses/gpl-3.0.txt)

#AnsibleRequires -CSharpUtil Ansible.Basic
#AnsibleRequires -PowerShell ..module_utils._CMPsSetupUtils


function Get-SUG {
    # Lookup the software update group by name or ID.
    # You can optionally pass in the ID, if the ID is coming from a SUG object instead of the
    # module parameter.
    param (
        [Parameter(Mandatory = $true)][object]$module,
        [Parameter(Mandatory = $false)][string]$id = ""
    )
    if ($id -eq "") {
        $id = $module.Params.id
    }
    $name = $module.Params.name
    if (($null -ne $id) -and ($id -ne "")) {
        $cmdlet_params = @{ Id = $id }
    }
    else {
        $cmdlet_params = @{ Name = $name }
    }

    try {
        return Get-CMSoftwareUpdateGroup @cmdlet_params
    }
    catch {
        $module.FailJson("Failed to search for software update group: $($_.Exception.Message)", $_)
    }
}


function Complete-SUGCreation {
    # Create a new software update group
    param (
        [Parameter(Mandatory = $true)][object]$module
    )
    $module.result.changed = $true
    if (-not $module.CheckMode) {
        # Map module parameters to cmdlet arguments
        $cmdlet_params = ConvertTo-CmdletParamsIfNotNull -moduleParamMapping @{
            name = @{ value = $module.Params.name; cmdletParamName = "Name" }
            description = @{ value = $module.Params.description; cmdletParamName = "Description" }
        }
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
        [Parameter(Mandatory = $true)][object]$sug
    )
    $test = @(
        @($module.Params.name, $sug.LocalizedDisplayName),
        @($module.Params.description, $sug.LocalizedDescription)
    )
    foreach ($test_item in $test) {
        if ($null -eq $test_item[0]) {
            continue
        }
        if ($test_item[0] -ne $test_item[1]) {
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
        [Parameter(Mandatory = $true)][object]$sug
    )
    # Test if the software update group needs to be updated
    $needs_update = Test-SoftwareUpdateGroupNeedsUpdate -module $module -sug $sug
    $module.result.changed = $needs_update

    # Update the software update group if it needs to be updated
    if (($needs_update) -and (-not $module.CheckMode)) {
        $cmdlet_params = ConvertTo-CmdletParamsIfNotNull -moduleParamMapping @{
            name = @{ value = $module.Params.name; cmdletParamName = "NewName" }
            description = @{ value = $module.Params.description; cmdletParamName = "Description" }
        }
        try {
            Set-CMSoftwareUpdateGroup @cmdlet_params -InputObject $sug
            # lookup the software update group again to get the updated object
            $sug = Get-SUG -module $module -id $sug.CI_ID
            if ($null -eq $sug) {
                $module.FailJson("Failed to update software update group. The software update group was not found after update.")
            }
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

# Setup PS environment
Import-CMPsModule -module $module
if (Test-CMSiteDrive -SiteCode $site_code) {
    Set-Location -LiteralPath "$($site_code):\"
}
else {
    $module.FailJson("Failed to connect to CM PS drive for site code $($site_code). It does not exist or is not accessible.")
}

# Check if the software update group exists
$software_update_group = Get-SUG -module $module

# Route to the appropriate function based on the software update group existence
if (($state -eq "absent") -and ($null -ne $software_update_group)) {
    Complete-SUGRemoval -module $module -sug $software_update_group
}
elseif (($state -eq "present") -and ($null -ne $software_update_group)) {
    Complete-SUGUpdate -module $module -sug $software_update_group
}
elseif (($state -eq "present") -and ($null -eq $software_update_group)) {
    if ($null -eq $module.params.name) {
        $module.FailJson("The name parameter is required when creating a new software update group.")
    }
    Complete-SUGCreation -module $module
}


$module.ExitJson()

# Copyright: (c) 2025, Ansible Project
# GNU General Public License v3.0+ (see COPYING or https://www.gnu.org/licenses/gpl-3.0.txt)

# NOTE: "return" in powershell does not work as many people expect. Read the PS docs before using it.

function Get-SoftwareUpdateObject {
    # Helper function to get a software update object from the site
    param (
        [Parameter(Mandatory = $true)][object]$module,
        [Parameter(Mandatory = $false)][AllowNull()][string]$software_update_id = $null,
        [Parameter(Mandatory = $false)][AllowNull()][string]$software_update_name = $null,
        [Parameter(Mandatory = $false)][boolean]$throw_error_if_not_found = $false
    )
    $software_update_object = $null
    if (-not [string]::IsNullOrEmpty($software_update_id)) {
        try {
            $software_update_object = Get-CMSoftwareUpdate -Id "$software_update_id"
        }
        catch {
            $module.FailJson("Failed to execute Get-CMSoftwareUpdate with ID '$software_update_id': $($_.Exception.Message)", $_)
        }
    }
    elseif (-not [string]::IsNullOrEmpty($software_update_name)) {
        try {
            $software_update_object = Get-CMSoftwareUpdate -Name "$software_update_name"
        }
        catch {
            $module.FailJson("Failed to execute Get-CMSoftwareUpdate with Name '$software_update_name': $($_.Exception.Message)", $_)
        }
    }
    else {
        $module.FailJson("Either software_update_id or software_update_name must be specified for Get-SoftwareUpdateObject")
    }

    if (($null -eq $software_update_object) -and ($throw_error_if_not_found)) {
        $module.FailJson("Failed to find a software update using the name '$software_update_name' or ID '$software_update_id'.")
    }

    return $software_update_object
}


function Get-SoftwareUpdateGroupObject {
    # Helper function to get a software update group object from the site
    param (
        [Parameter(Mandatory = $true)][object]$module,
        [Parameter(Mandatory = $false)][AllowNull()][string]$software_update_group_id = $null,
        [Parameter(Mandatory = $false)][AllowNull()][string]$software_update_group_name = $null,
        [Parameter(Mandatory = $false)][boolean]$throw_error_if_not_found = $false
    )
    $software_update_group_object = $null
    if (-not [string]::IsNullOrEmpty($software_update_group_id)) {
        try {
            $software_update_group_object = Get-CMSoftwareUpdateGroup -Id "$software_update_group_id"
        }
        catch {
            $module.FailJson("Failed to execute Get-CMSoftwareUpdateGroup with ID '$software_update_group_id': $($_.Exception.Message)", $_)
        }
    }
    elseif (-not [string]::IsNullOrEmpty($software_update_group_name)) {
        try {
            $software_update_group_object = Get-CMSoftwareUpdateGroup -Name "$software_update_group_name"
        }
        catch {
            $module.FailJson("Failed to execute Get-CMSoftwareUpdateGroup with Name '$software_update_group_name': $($_.Exception.Message)", $_)
        }
    }
    else {
        $module.FailJson("Either software_update_group_id or software_update_group_name must be specified for Get-SoftwareUpdateGroupObject")
    }

    if (($null -eq $software_update_group_object) -and ($throw_error_if_not_found)) {
        $module.FailJson("Failed to find a software update group using the name '$software_update_group_name' or ID '$software_update_group_id'.")
    }

    return $software_update_group_object
}


function Get-CollectionObject {
    # Helper function to get a collection object from the site, using module parameters as needed.
    param (
        [Parameter(Mandatory = $true)][object]$module,
        [Parameter(Mandatory = $false)][AllowNull()][string]$collection_id = $null,
        [Parameter(Mandatory = $false)][AllowNull()][string]$collection_name = $null,
        [Parameter(Mandatory = $false)][boolean]$throw_error_if_not_found = $false
    )
    $collection_object = $null
    if (-not [string]::IsNullOrEmpty($collection_id)) {
        try {
            $collection_object = Get-CMCollection -Id "$collection_id"
        }
        catch {
            $module.FailJson("Failed to execute Get-CMCollection with ID '$collection_id': $($_.Exception.Message)", $_)
        }
    }
    elseif (-not [string]::IsNullOrEmpty($collection_name)) {
        try {
            $collection_object = Get-CMCollection -Name "$collection_name"
        }
        catch {
            $module.FailJson("Failed to execute Get-CMCollection with Name '$collection_name': $($_.Exception.Message)", $_)
        }
    }
    else {
        $module.FailJson("Either collection_id or collection_name must be specified for Get-CollectionObject")
    }

    if (($null -eq $collection_object) -and ($throw_error_if_not_found)) {
        $module.FailJson("Failed to find a collection using the name '$collection_name' or ID '$collection_id'.")
    }

    return $collection_object
}

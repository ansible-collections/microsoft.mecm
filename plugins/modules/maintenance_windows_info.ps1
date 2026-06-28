#!powershell

# Copyright: (c) 2025, Ansible Project
# GNU General Public License v3.0+ (see COPYING or https://www.gnu.org/licenses/gpl-3.0.txt)

#AnsibleRequires -CSharpUtil Ansible.Basic
#AnsibleRequires -PowerShell ..module_utils._CMPsSetupUtils
#AnsibleRequires -PowerShell ..module_utils._MaintenanceWindowUtils


$spec = @{
    options = @{
        site_code = @{ type = 'str'; required = $true }
        device_collection_name = @{ type = 'str'; required = $true }
        name = @{ type = 'str'; required = $false }
    }
    supports_check_mode = $true
}

$module = [Ansible.Basic.AnsibleModule]::Create($args, $spec)
$module.result.maintenance_windows = @()
$module.result.changed = $false

$site_code = $module.Params.site_code
$device_collection_name = $module.Params.device_collection_name
$name = $module.Params.name

Import-CMPsModule -module $module
Test-CMSiteNameAndConnect -module $module -SiteCode $site_code

# Verify the device collection exists before querying its maintenance windows.
$collection = Get-CMCollection -Name $device_collection_name -ErrorAction SilentlyContinue
if ($null -eq $collection) {
    $module.FailJson("Device collection '$device_collection_name' does not exist.")
}
$collection_id = $collection.CollectionID

if (-not [string]::IsNullOrEmpty($name)) {
    # Retrieve a single named maintenance window.
    try {
        $mws = @(Get-CMMaintenanceWindow -CollectionID $collection_id -MaintenanceWindowName $name -DisableWildcardHandling -ErrorAction Stop)
    }
    catch {
        $module.FailJson(
            "Failed to query maintenance window '$name' on collection '$device_collection_name': $($_.Exception.Message)",
            $_
        )
    }

    if (-not $mws) {
        $module.Warn("Maintenance window '$name' does not exist on collection '$device_collection_name'.")
        $module.ExitJson()
    }
}
else {
    # Retrieve all maintenance windows for the collection.
    try {
        $mws = @(Get-CMMaintenanceWindow -CollectionID $collection_id -ErrorAction Stop)
    }
    catch {
        $module.FailJson(
            "Failed to query maintenance windows on collection '$device_collection_name': $($_.Exception.Message)",
            $_
        )
    }
}

foreach ($mw in $mws) {
    if ($null -eq $mw) { continue }
    $module.result.maintenance_windows += Format-MaintenanceWindowResult -mw $mw
}

$module.ExitJson()

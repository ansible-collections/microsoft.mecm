#!powershell

# Copyright: (c) 2026, Ansible Project
# GNU General Public License v3.0+ (see COPYING or https://www.gnu.org/licenses/gpl-3.0.txt)

#AnsibleRequires -CSharpUtil Ansible.Basic
#AnsibleRequires -PowerShell ..module_utils._CMPsSetupUtils


function ConvertFrom-CMRefreshType {
    param ([int]$value)
    switch ($value) {
        1 { return 'Manual' }
        2 { return 'Periodic' }
        4 { return 'Continuous' }
        6 { return 'Both' }
        default { return "Unknown ($value)" }
    }
}


$spec = @{
    options = @{
        site_code = @{ type = 'str'; required = $true }
        name = @{ type = 'str'; required = $false }
    }
    supports_check_mode = $true
}

$module = [Ansible.Basic.AnsibleModule]::Create($args, $spec)
$module.result.device_collections = @()
$module.result.changed = $false

$site_code = $module.Params.site_code
$name = $module.Params.name

Import-CMPsModule -module $module
Test-CMSiteNameAndConnect -SiteCode $site_code -Module $module

if (-not [string]::IsNullOrEmpty($name)) {
    try {
        $collections = @(Get-CMDeviceCollection -Name $name -ErrorAction Stop)
    }
    catch {
        $module.FailJson("Failed to query device collection '$name': $($_.Exception.Message)", $_)
    }
    if (-not $collections) {
        $module.Warn("Device collection '$name' does not exist.")
        $module.ExitJson()
    }
}
else {
    try {
        $collections = @(Get-CMDeviceCollection -ErrorAction Stop)
    }
    catch {
        $module.FailJson("Failed to query device collections: $($_.Exception.Message)", $_)
    }
}

foreach ($collection in $collections) {
    if ($null -eq $collection) { continue }
    $module.result.device_collections += @{
        name = $collection.Name
        collection_id = $collection.CollectionID
        limiting_collection_name = $collection.LimitToCollectionName
        refresh_type = ConvertFrom-CMRefreshType -value ([int]$collection.RefreshType)
        member_count = $collection.MemberCount
        comment = $collection.Comment
        is_built_in = [bool]$collection.IsBuiltIn
    }
}

$module.ExitJson()

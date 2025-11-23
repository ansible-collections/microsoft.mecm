#!powershell

# Copyright: (c) 2025, Ansible Project
# GNU General Public License v3.0+ (see COPYING or https://www.gnu.org/licenses/gpl-3.0.txt)

#AnsibleRequires -CSharpUtil Ansible.Basic
#AnsibleRequires -PowerShell ..module_utils._CMPsSetupUtils

$spec = @{
    options = @{
        site_code = @{ type = 'str'; required = $true }
        name = @{ type = 'str'; required = $false }
        id = @{ type = 'str'; required = $false }
    }
    mutually_exclusive = @(
        , @("name", "id")
    )
    supports_check_mode = $true
}


$module = [Ansible.Basic.AnsibleModule]::Create($args, $spec)
$module.result.software_update_groups = @()

# Map frequently used module parameters to cmdlet arguments
$site_code = $module.Params.site_code
$name = $module.Params.name
$id = $module.Params.id

# Setup PS environment
Import-CMPsModule -module $module
if (Test-CMSiteDrive -SiteCode $site_code) {
    Set-Location -LiteralPath "$($site_code):\"
}
else {
    $module.FailJson("Failed to connect to CM PS drive for site code $($site_code): $($_.Exception.Message)")
}

# Setup cmdlet parameters
$cmdlet_params = @{}
if ($null -ne $name) {
    $cmdlet_params = @{ Name = $name }
}
elseif ($null -ne $id) {
    $cmdlet_params = @{ Id = $id }
}

# Run cmdlet to get status messages
try {
    $software_update_groups = Get-CMSoftwareUpdateGroup @cmdlet_params
}
catch {
    $module.FailJson("Failed to get software update groups: $($_.Exception.Message)", $_)
}

# Format output. Dumping the messages to JSON results in a ton of data, so we need to pick and choose which properties to include.
$software_update_groups_formatted = @()
foreach ($software_update_group in $software_update_groups) {
    $software_update_groups_formatted += @{
        name = $software_update_group.LocalizedDisplayName
        id = $software_update_group.CI_ID.ToString()
        updates = $software_update_group.Updates
        contains_expired_updates = ($software_update_group.ContainsExpiredUpdates -eq $true) # this can be null, so we need to convert to a bool
        contains_superseded_updates = ($software_update_group.ContainsSupersededUpdates -eq $true)
        created_by = $software_update_group.CreatedBy
        description = $software_update_group.LocalizedDescription
        created_time = $software_update_group.DateCreated.ToString("yyyy-MM-dd HH:mm:ss")
        is_bundle = $software_update_group.IsBundle
        is_deployed = $software_update_group.IsDeployed
        is_digest = $software_update_group.IsDigest
        is_enabled = $software_update_group.IsEnabled
        is_expired = $software_update_group.IsExpired
        is_hidden = $software_update_group.IsHidden
        is_latest = $software_update_group.IsLatest
        is_provisioned = $software_update_group.IsProvisioned
        is_quarantined = $software_update_group.IsQuarantined
        is_superseded = $software_update_group.IsSuperseded
        is_user_defined = $software_update_group.IsUserDefined
        is_version_compatible = ($software_update_group.IsVersionCompatible -eq $true)
        last_modified_by = $software_update_group.LastModifiedBy
        last_modified_time = ""
        last_status_time = ""
        effective_date = ""
    }
    $datetime_or_null_attrs = @{
        last_modified_time = $software_update_group.DateLastModified
        last_status_time = $software_update_group.LastStatusTime
        effective_date = $software_update_group.EffectiveDate
    }
    foreach ($output_key in $datetime_or_null_attrs.Keys) {
        if ($null -ne $datetime_or_null_attrs[$output_key]) {
            $software_update_groups_formatted[-1][$output_key] = $datetime_or_null_attrs[$output_key].ToString("yyyy-MM-dd HH:mm:ss")
        }
    }
}

$module.result.software_update_groups = $software_update_groups_formatted
$module.ExitJson()

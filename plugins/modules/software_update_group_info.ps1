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
Test-CMSiteNameAndConnect -module $module -site_code $site_code

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

if ($null -eq $software_update_groups) {
    $module.ExitJson()
}

# Format output. Dumping the messages to JSON results in a ton of data, so we need to pick and choose which properties to include.
$software_update_groups_formatted = @()
foreach ($software_update_group in $software_update_groups) {
    $software_update_groups_formatted += @{
        name = $software_update_group.LocalizedDisplayName
        id = $software_update_group.CI_ID.ToString()
        updates = $software_update_group.Updates
        contains_expired_updates = $software_update_group.ContainsExpiredUpdates
        contains_superseded_updates = $software_update_group.ContainsSupersededUpdates
        created_by = $software_update_group.CreatedBy
        description = $software_update_group.LocalizedDescription
        created_time = Format-DateTimeAsStringSafely -dateTimeObject $software_update_group.DateCreated
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
        last_modified_by = $software_update_group.LastModifiedBy
        last_modified_time = Format-DateTimeAsStringSafely -dateTimeObject $software_update_group.DateLastModified
        last_status_time = Format-DateTimeAsStringSafely -dateTimeObject $software_update_group.LastStatusTime
        effective_date = Format-DateTimeAsStringSafely -dateTimeObject $software_update_group.EffectiveDate
    }
}

$module.result.software_update_groups = $software_update_groups_formatted
$module.ExitJson()

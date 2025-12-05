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
Test-CMSiteNameAndConnect -module $module -SiteCode $site_code

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
$software_update_groups_formatted = @($software_update_groups | ForEach-Object {
        @{
            name = $_.LocalizedDisplayName
            id = $_.CI_ID.ToString()
            updates = $_.Updates
            contains_expired_updates = $_.ContainsExpiredUpdates
            contains_superseded_updates = $_.ContainsSupersededUpdates
            created_by = $_.CreatedBy
            description = $_.LocalizedDescription
            created_time = Format-DateTimeAsStringSafely -dateTimeObject $_.DateCreated
            is_bundle = $_.IsBundle
            is_deployed = $_.IsDeployed
            is_digest = $_.IsDigest
            is_enabled = $_.IsEnabled
            is_expired = $_.IsExpired
            is_hidden = $_.IsHidden
            is_latest = $_.IsLatest
            is_provisioned = $_.IsProvisioned
            is_quarantined = $_.IsQuarantined
            is_superseded = $_.IsSuperseded
            is_user_defined = $_.IsUserDefined
            last_modified_by = $_.LastModifiedBy
            last_modified_time = Format-DateTimeAsStringSafely -dateTimeObject $_.DateLastModified
            last_status_time = Format-DateTimeAsStringSafely -dateTimeObject $_.LastStatusTime
            effective_date = Format-DateTimeAsStringSafely -dateTimeObject $_.EffectiveDate
        }
    })
if ($null -ne $software_update_groups_formatted) {
    $module.result.software_update_groups = $software_update_groups_formatted
}

$module.ExitJson()

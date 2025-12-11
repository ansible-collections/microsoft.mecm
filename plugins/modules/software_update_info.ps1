#!powershell

# Copyright: (c) 2025, Ansible Project
# GNU General Public License v3.0+ (see COPYING or https://www.gnu.org/licenses/gpl-3.0.txt)

#AnsibleRequires -CSharpUtil Ansible.Basic
#AnsibleRequires -PowerShell ..module_utils._CMPsSetupUtils


function Get-SingleSoftwareUpdateObject {
    param (
        [Parameter(Mandatory = $true)][object]$module,
        [Parameter(Mandatory = $false)][AllowNull()][string]$id = $null,
        [Parameter(Mandatory = $false)][AllowNull()][string]$name = $null
    )
    # Setup cmdlet parameters
    $cmdlet_params = @{ Fast = $true }
    if (-not [string]::IsNullOrEmpty($name)) {
        $cmdlet_params["Name"] = $name
    }
    elseif (-not [string]::IsNullOrEmpty($id)) {
        $cmdlet_params["Id"] = $id
    }

    # Run cmdlet to get status messages
    try {
        return Get-CMSoftwareUpdate @cmdlet_params
    }
    catch {
        $module.FailJson("Failed to get software update groups: $($_.Exception.Message)", $_)
    }
}


function Get-SoftwareUpdateObjectsByArticleIdArray {
    param (
        [Parameter(Mandatory = $true)][object]$module,
        [Parameter(Mandatory = $true)][array]$article_ids
    )
    # Setup cmdlet parameters
    try {
        $software_update_objects = foreach ($article_id in $article_ids) {
            Get-CMSoftwareUpdate -ArticleId $article_id -Fast
        }
    }
    catch {
        $module.FailJson("Failed to get software updates by article IDs: $($_.Exception.Message)", $_)
    }
    return $software_update_objects
}


$spec = @{
    options = @{
        site_code = @{ type = 'str'; required = $true }
        name = @{ type = 'str'; required = $false }
        id = @{ type = 'str'; required = $false }
        article_ids = @{ type = 'list'; required = $false; elements = 'str' }
    }
    mutually_exclusive = @(
        , @("name", "id", "article_ids")
    )
    supports_check_mode = $true
}


$module = [Ansible.Basic.AnsibleModule]::Create($args, $spec)
$module.Result.software_updates = @()

# Map frequently used module parameters to cmdlet arguments
$site_code = $module.Params.site_code
$name = $module.Params.name
$id = $module.Params.id
$article_ids = $module.Params.article_ids

# Setup PS environment
Import-CMPsModule -module $module
Test-CMSiteNameAndConnect -module $module -SiteCode $site_code

# Get update objects
if ($null -ne $article_ids) {
    $software_update_objects = Get-SoftwareUpdateObjectsByArticleIdArray -module $module -article_ids $article_ids
}
else {
    $software_update_objects = @(Get-SingleSoftwareUpdateObject -module $module -name $name -id $id)
}

if ($null -eq $software_update_objects) {
    $module.ExitJson()
}

# Format output. Dumping the messages to JSON results in a ton of data, so we need to pick and choose which properties to include.
$software_updates_formatted = @($software_update_objects | ForEach-Object {
        @{
            name = $_.LocalizedDisplayName
            id = $_.CI_ID.ToString()
            article_id = $_.ArticleId
            is_deployable = $_.IsDeployable
            is_deployed = $_.IsDeployed
            is_enabled = $_.IsEnabled
            is_expired = $_.IsExpired
            is_hidden = $_.IsHidden
            is_latest = $_.IsLatest
            is_superseded = $_.IsSuperseded
            is_user_defined = $_.IsUserDefined
            last_status_time = Format-DateTimeAsStringSafely -dateTimeObject $_.LastStatusTime
            last_modified_by = $_.LastModifiedBy
            created_time = Format-DateTimeAsStringSafely -dateTimeObject $_.DateCreated
            posted_time = Format-DateTimeAsStringSafely -dateTimeObject $_.DatePosted
            last_modified_time = Format-DateTimeAsStringSafely -dateTimeObject $_.DateLastModified
            category_names = $_.LocalizedCategoryInstanceNames
            description = $_.LocalizedDescription
            informational_url = $_.LocalizedInformativeURL
        }
    })
if ($null -ne $software_updates_formatted) {
    $module.Result.software_updates = $software_updates_formatted
}

$module.ExitJson()

#!powershell

# Copyright: (c) 2025, Ansible Project
# GNU General Public License v3.0+ (see COPYING or https://www.gnu.org/licenses/gpl-3.0.txt)

#AnsibleRequires -CSharpUtil Ansible.Basic
#AnsibleRequires -PowerShell ..module_utils._CMPsSetupUtils

$spec = @{
    options = @{
        site_code = @{ type = 'str'; required = $true }
        computer_name = @{ type = 'str'; required = $false }
        severity = @{ type = 'str'; required = $false ; default = "all" ; choices = @("all", "error", "warning", "information") }
        component = @{ type = 'str'; required = $false }
        search_start_time = @{ type = 'str'; required = $false }
    }
    supports_check_mode = $true
}

$module = [Ansible.Basic.AnsibleModule]::Create($args, $spec)
$module.result.site_status_messages = @()

# Map frequently used module parameters to cmdlet arguments
$site_code = $module.Params.site_code
$computer_name = $module.Params.computer_name
if ($null -eq $computer_name) {
    $computer_name = Get-LocalComputerFQDN
}

# Setup PS environment
Import-CMPsModule -module $module
if (Test-CMSiteDrive -SiteCode $site_code) {
    Set-Location -LiteralPath "$($site_code):\"
}
else {
    $module.FailJson("Failed to connect to CM PS drive for site code $($site_code): $($_.Exception.Message)")
}

# Setup cmdlet parameters
$cmdlet_params = @{
    SiteCode = $site_code
    Severity = $module.Params.severity
    ComputerName = $computer_name
}
if ($null -ne $module.Params.search_start_time) {
    try {
        $search_start_time = (Get-Date $module.Params.search_start_time).ToString()
    }
    catch {
        $module.FailJson("Failed to parse search_start_time: $($_.Exception.Message)")
    }
    $cmdlet_params.StartDateTime = $search_start_time
}
if ($null -ne $module.Params.component) {
    $cmdlet_params.Component = $module.Params.component
}

# Run cmdlet to get status messages
try {
    $site_status_messages = Get-CMSiteStatusMessage @cmdlet_params
}
catch {
    $module.FailJson("Failed to get site status messages: $($_.Exception.Message)", $_)
}

# Format output. Dumping the messages to JSON results in a ton of data, so we need to pick and choose which properties to include.
$site_status_messages_formatted = @()
foreach ($message in $site_status_messages) {
    $site_status_messages_formatted += @{
        message_id = $message.MessageId
        severity = ConvertTo-SeverityString -SeverityCode $message.Severity
        timestamp = $message.Time.ToString("yyyy-MM-dd HH:mm:ss")
        site_code = $message.SiteCode
        computer_name = $message.PSComputerName
        component = $message.Component
        module = $message.ModuleName
    }
}

$module.result.site_status_messages = $site_status_messages_formatted
$module.ExitJson()

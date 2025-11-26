#!powershell

# Copyright: (c) 2025, Ansible Project
# GNU General Public License v3.0+ (see COPYING or https://www.gnu.org/licenses/gpl-3.0.txt)

#AnsibleRequires -CSharpUtil Ansible.Basic
#AnsibleRequires -PowerShell ..module_utils._CMPsSetupUtils

$spec = @{
    options = @{
        site_code = @{ type = 'str'; required = $true }
        state = @{ type = 'str'; required = $false; default = "present" ; choices = @("present", "absent") }
    }
    supports_check_mode = $true
}

$module = [Ansible.Basic.AnsibleModule]::Create($args, $spec)

# Map module parameters to cmdlet arguments
$site_code = $module.Params.site_code
$state = $module.Params.state

# Setup PS environment
Import-CMPsModule -module $module

# Check if the site drive exists
$drive_exists = Test-CMSiteDrive -SiteCode $site_code
if (
    ($state -eq "present" -and $drive_exists) -or
    ($state -eq "absent" -and -not $drive_exists)
) {
    $module.ExitJson()
}

# Something needs to be changed. Exit if in check mode
$module.result.changed = $true
if ($module.CheckMode) {
    $module.ExitJson()
}

# Create or remove the site drive
try {
    if ($state -eq "present") {
        $computer_name = Get-LocalComputerFQDN
        New-PSDrive -Name $site_code -PSProvider CMSite -Root $computer_name
    }
    else {
        Remove-PSDrive -Name $site_code
    }
}
catch {
    $module.FailJson("Failed to update site drive: $($_.Exception.Message)", $_)
}
$module.ExitJson()

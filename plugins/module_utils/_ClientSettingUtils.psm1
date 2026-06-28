# Copyright: (c) 2025, Ansible Project
# GNU General Public License v3.0+ (see COPYING or https://www.gnu.org/licenses/gpl-3.0.txt)

# NOTE: "return" in powershell does not work as many people expect. Read the PS docs before using it.

# Maps integer Type values returned by Get-CMClientSetting to human-readable strings.
# 0 = default (read-only, cannot be created via this module)
# 1 = device
# 2 = user
$CLIENT_SETTING_TYPE_INT = @{
    0 = 'default'
    1 = 'device'
    2 = 'user'
}


function ConvertTo-ClientSettingTypeString {
    param (
        [Parameter(Mandatory = $true)][int]$TypeInt
    )
    if ($CLIENT_SETTING_TYPE_INT.ContainsKey($TypeInt)) {
        return $CLIENT_SETTING_TYPE_INT[$TypeInt]
    }
    return $TypeInt.ToString()
}


function Format-ClientSettingResult {
    param (
        [Parameter(Mandatory = $true)][object]$setting
    )
    $type_int = [int]$setting.Type
    $type_str = ConvertTo-ClientSettingTypeString -TypeInt $type_int

    return @{
        name = $setting.Name
        description = if ($null -ne $setting.Description) { $setting.Description } else { '' }
        type = $type_str
        priority = [int]$setting.Priority
        settings_id = $setting.SettingsID.ToString()
    }
}

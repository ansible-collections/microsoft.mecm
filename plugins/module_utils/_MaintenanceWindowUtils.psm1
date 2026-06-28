# Copyright: (c) 2025, Ansible Project
# GNU General Public License v3.0+ (see COPYING or https://www.gnu.org/licenses/gpl-3.0.txt)

# NOTE: "return" in powershell does not work as many people expect. Read the PS docs before using it.

$SERVICE_WINDOW_TYPE_MAP = @{
    1 = 'Any'
    4 = 'SoftwareUpdatesOnly'
    5 = 'TaskSequencesOnly'
}


function ConvertTo-ServiceWindowTypeInt {
    param (
        [Parameter(Mandatory = $true)][string]$ApplyTo
    )
    return ($SERVICE_WINDOW_TYPE_MAP.GetEnumerator() | Where-Object { $_.Value -eq $ApplyTo } | Select-Object -First 1).Key
}


function Format-MaintenanceWindowResult {
    param (
        [Parameter(Mandatory = $true)][object]$mw
    )
    $type_int = [int]$mw.ServiceWindowType
    $apply_to_str = $SERVICE_WINDOW_TYPE_MAP[$type_int]
    if (-not $apply_to_str) {
        $apply_to_str = $type_int.ToString()
    }
    return @{
        name = $mw.Name
        service_window_id = $mw.ServiceWindowID.ToString()
        is_enabled = [bool]$mw.IsEnabled
        apply_to = $apply_to_str
        duration = [int]$mw.Duration
        service_window_schedules = $mw.ServiceWindowSchedules
    }
}

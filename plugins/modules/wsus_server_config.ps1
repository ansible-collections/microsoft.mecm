#!powershell

# Copyright: (c) 2025, Ansible Project
# GNU General Public License v3.0+ (see COPYING or https://www.gnu.org/licenses/gpl-3.0.txt)

#AnsibleRequires -CSharpUtil Ansible.Basic
#AnsibleRequires -PowerShell ..module_utils._WsusUtils


function Test-WsusListChanged {
    <#
    .SYNOPSIS
    Returns $true when two string lists differ, ignoring order and case.
    #>
    param (
        [AllowEmptyCollection()][string[]]$current,
        [AllowEmptyCollection()][string[]]$desired
    )
    $current_sorted = @($current | ForEach-Object { $_.ToLower() } | Sort-Object)
    $desired_sorted = @($desired | ForEach-Object { $_.ToLower() } | Sort-Object)
    if ($current_sorted.Count -ne $desired_sorted.Count) {
        return $true
    }
    for ($i = 0; $i -lt $current_sorted.Count; $i++) {
        if ($current_sorted[$i] -ne $desired_sorted[$i]) {
            return $true
        }
    }
    return $false
}


function ConvertTo-WsusTimeSpan {
    <#
    .SYNOPSIS
    Parses an "HH:MM" string into a TimeSpan, failing the module on an invalid value.
    #>
    param (
        [Parameter(Mandatory = $true)][object]$module,
        [Parameter(Mandatory = $true)][string]$value
    )
    $parts = $value -split ':'
    $hours = 0
    $minutes = 0
    if (($parts.Count -ne 2) -or
        (-not [int]::TryParse($parts[0], [ref]$hours)) -or
        (-not [int]::TryParse($parts[1], [ref]$minutes)) -or
        ($hours -lt 0) -or ($hours -gt 23) -or ($minutes -lt 0) -or ($minutes -gt 59)) {
        $module.FailJson("Invalid synchronize_time_of_day value '$value'. Expected an 'HH:MM' 24-hour time between '00:00' and '23:59'.")
    }
    return [TimeSpan]::new($hours, $minutes, 0)
}


function Confirm-WsusTitle {
    <#
    .SYNOPSIS
    Validates that every requested title exists among the available WSUS titles.
    #>
    param (
        [Parameter(Mandatory = $true)][object]$module,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$requested,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$available,
        [Parameter(Mandatory = $true)][string]$param_name
    )
    foreach ($title in $requested) {
        $match = $available | Where-Object { $_ -ieq $title } | Select-Object -First 1
        if ($null -eq $match) {
            $available_list = ($available | Sort-Object) -join "', '"
            $module.FailJson("$param_name value '$title' was not found on the WSUS server. Available values: '$available_list'.")
        }
    }
}


function Set-WsusServerConfiguration {
    <#
    .SYNOPSIS
    Reconciles the synchronization source, update languages, and targeting mode.

    .DESCRIPTION
    These settings all live on the server configuration object and share a single Save(),
    so they are handled together. Sets $module.result.changed when a change is needed and,
    unless check mode is enabled, applies the change. Returns nothing.
    #>
    param (
        [Parameter(Mandatory = $true)][object]$module,
        [Parameter(Mandatory = $true)][object]$wsus
    )

    $config = $wsus.GetConfiguration()
    $needs_save = $false

    # --- Synchronization source ---
    if ($null -ne $module.Params.sync_source) {
        $sync_changed = $false
        if ($module.Params.sync_source -eq 'microsoft_update') {
            if (-not $config.SyncFromMicrosoftUpdate) {
                $sync_changed = $true
            }
        }
        else {
            if ($config.SyncFromMicrosoftUpdate) {
                $sync_changed = $true
            }
            if ($module.Params.upstream_server_name -ne $config.UpstreamWsusServerName) {
                $sync_changed = $true
            }
            if (($null -ne $module.Params.upstream_server_port) -and
                ($module.Params.upstream_server_port -ne $config.UpstreamWsusServerPortNumber)) {
                $sync_changed = $true
            }
            if (($null -ne $module.Params.upstream_server_use_ssl) -and
                ([bool]$module.Params.upstream_server_use_ssl -ne [bool]$config.UpstreamWsusServerUseSsl)) {
                $sync_changed = $true
            }
        }

        if ($sync_changed) {
            $module.result.changed = $true
            if (-not $module.CheckMode) {
                try {
                    if ($module.Params.sync_source -eq 'microsoft_update') {
                        Set-WsusServerSynchronization -UpdateServer $wsus -SyncFromMU
                    }
                    else {
                        $sync_params = @{
                            UpdateServer = $wsus
                            UssServerName = $module.Params.upstream_server_name
                        }
                        if ($null -ne $module.Params.upstream_server_port) {
                            $sync_params['PortNumber'] = $module.Params.upstream_server_port
                        }
                        if ([bool]$module.Params.upstream_server_use_ssl) {
                            $sync_params['UssUseSsl'] = $true
                        }
                        Set-WsusServerSynchronization @sync_params
                    }
                }
                catch {
                    $module.FailJson("Failed to set WSUS synchronization source: $($_.Exception.Message)", $_)
                }
                # Set-WsusServerSynchronization saves the configuration itself, so re-fetch it
                # before applying the remaining configuration settings.
                $config = $wsus.GetConfiguration()
            }
        }
    }

    # --- Update languages ---
    if (($null -ne $module.Params.all_update_languages_enabled) -and
        ([bool]$module.Params.all_update_languages_enabled -ne [bool]$config.AllUpdateLanguagesEnabled)) {
        $module.result.changed = $true
        if (-not $module.CheckMode) {
            $config.AllUpdateLanguagesEnabled = [bool]$module.Params.all_update_languages_enabled
            $needs_save = $true
        }
    }
    if ($null -ne $module.Params.enabled_languages) {
        $current_languages = @()
        if (-not $config.AllUpdateLanguagesEnabled) {
            $current_languages = @($config.GetEnabledUpdateLanguages())
        }
        if (Test-WsusListChanged -current $current_languages -desired $module.Params.enabled_languages) {
            $module.result.changed = $true
            if (-not $module.CheckMode) {
                try {
                    $config.SetEnabledUpdateLanguages([string[]]$module.Params.enabled_languages)
                }
                catch {
                    $module.FailJson("Failed to set enabled update languages: $($_.Exception.Message)", $_)
                }
                $needs_save = $true
            }
        }
    }

    # --- Targeting mode ---
    if (($null -ne $module.Params.targeting_mode) -and
        ($module.Params.targeting_mode -ne $config.TargetingMode.ToString())) {
        $module.result.changed = $true
        if (-not $module.CheckMode) {
            $config.TargetingMode = $module.Params.targeting_mode
            $needs_save = $true
        }
    }

    if ($needs_save -and (-not $module.CheckMode)) {
        try {
            $config.Save()
        }
        catch {
            $module.FailJson("Failed to save WSUS server configuration: $($_.Exception.Message)", $_)
        }
    }
}


function Set-WsusSyncSchedule {
    <#
    .SYNOPSIS
    Reconciles the automatic synchronization schedule on the subscription.

    .DESCRIPTION
    Sets $module.result.changed when a change is needed and, unless check mode is enabled,
    applies the change and saves the subscription. Returns nothing.
    #>
    param (
        [Parameter(Mandatory = $true)][object]$module,
        [Parameter(Mandatory = $true)][object]$subscription
    )

    $needs_save = $false

    $desired_time_span = $null
    if ($null -ne $module.Params.synchronize_time_of_day) {
        $desired_time_span = ConvertTo-WsusTimeSpan -module $module -value $module.Params.synchronize_time_of_day
    }

    if (($null -ne $module.Params.synchronize_automatically) -and
        ([bool]$module.Params.synchronize_automatically -ne [bool]$subscription.SynchronizeAutomatically)) {
        $module.result.changed = $true
        if (-not $module.CheckMode) {
            $subscription.SynchronizeAutomatically = [bool]$module.Params.synchronize_automatically
            $needs_save = $true
        }
    }
    if (($null -ne $desired_time_span) -and
        ($desired_time_span -ne $subscription.SynchronizeAutomaticallyTimeOfDay)) {
        $module.result.changed = $true
        if (-not $module.CheckMode) {
            $subscription.SynchronizeAutomaticallyTimeOfDay = $desired_time_span
            $needs_save = $true
        }
    }
    if (($null -ne $module.Params.number_of_synchronizations_per_day) -and
        ($module.Params.number_of_synchronizations_per_day -ne $subscription.NumberOfSynchronizationsPerDay)) {
        $module.result.changed = $true
        if (-not $module.CheckMode) {
            $subscription.NumberOfSynchronizationsPerDay = $module.Params.number_of_synchronizations_per_day
            $needs_save = $true
        }
    }

    if ($needs_save -and (-not $module.CheckMode)) {
        try {
            $subscription.Save()
        }
        catch {
            $module.FailJson("Failed to save WSUS subscription: $($_.Exception.Message)", $_)
        }
    }
}


function Set-WsusProductSelection {
    <#
    .SYNOPSIS
    Reconciles the enabled products to match the desired set (enable desired, disable the rest).

    .DESCRIPTION
    Validates the requested titles, sets $module.result.changed when the enabled set differs,
    and applies the change unless check mode is enabled. Returns nothing.
    #>
    param (
        [Parameter(Mandatory = $true)][object]$module,
        [Parameter(Mandatory = $true)][object]$wsus,
        [Parameter(Mandatory = $true)][object]$subscription
    )

    if ($null -eq $module.Params.products) {
        return
    }

    $all_products = @(Get-WsusProduct -UpdateServer $wsus)
    Confirm-WsusTitle -module $module -requested $module.Params.products `
        -available @($all_products | ForEach-Object { $_.Product.Title }) -param_name 'products'

    $current_products = @(Get-WsusEnabledProductTitle -subscription $subscription)
    if (-not (Test-WsusListChanged -current $current_products -desired $module.Params.products)) {
        return
    }

    $module.result.changed = $true
    if ($module.CheckMode) {
        return
    }

    $desired = @($module.Params.products | ForEach-Object { $_.ToLower() })
    try {
        foreach ($product in $all_products) {
            $is_desired = $desired -contains $product.Product.Title.ToLower()
            $product | Set-WsusProduct -Disable:(-not $is_desired)
        }
    }
    catch {
        $module.FailJson("Failed to set WSUS products: $($_.Exception.Message)", $_)
    }
}


function Set-WsusClassificationSelection {
    <#
    .SYNOPSIS
    Reconciles the enabled classifications to match the desired set (enable desired, disable the rest).

    .DESCRIPTION
    Validates the requested titles, sets $module.result.changed when the enabled set differs,
    and applies the change unless check mode is enabled. Returns nothing.
    #>
    param (
        [Parameter(Mandatory = $true)][object]$module,
        [Parameter(Mandatory = $true)][object]$wsus,
        [Parameter(Mandatory = $true)][object]$subscription
    )

    if ($null -eq $module.Params.classifications) {
        return
    }

    $all_classifications = @(Get-WsusClassification -UpdateServer $wsus)
    Confirm-WsusTitle -module $module -requested $module.Params.classifications `
        -available @($all_classifications | ForEach-Object { $_.Classification.Title }) -param_name 'classifications'

    $current_classifications = @(Get-WsusEnabledClassificationTitle -subscription $subscription)
    if (-not (Test-WsusListChanged -current $current_classifications -desired $module.Params.classifications)) {
        return
    }

    $module.result.changed = $true
    if ($module.CheckMode) {
        return
    }

    $desired = @($module.Params.classifications | ForEach-Object { $_.ToLower() })
    try {
        foreach ($classification in $all_classifications) {
            $is_desired = $desired -contains $classification.Classification.Title.ToLower()
            $classification | Set-WsusClassification -Disable:(-not $is_desired)
        }
    }
    catch {
        $module.FailJson("Failed to set WSUS classifications: $($_.Exception.Message)", $_)
    }
}


$spec = @{
    options = @{
        server_name = @{ type = 'str'; required = $false }
        port = @{ type = 'int'; required = $false }
        use_ssl = @{ type = 'bool'; required = $false; default = $false }
        sync_source = @{ type = 'str'; required = $false; choices = @('microsoft_update', 'upstream_server') }
        upstream_server_name = @{ type = 'str'; required = $false }
        upstream_server_port = @{ type = 'int'; required = $false }
        upstream_server_use_ssl = @{ type = 'bool'; required = $false }
        all_update_languages_enabled = @{ type = 'bool'; required = $false }
        enabled_languages = @{ type = 'list'; elements = 'str'; required = $false }
        products = @{ type = 'list'; elements = 'str'; required = $false }
        classifications = @{ type = 'list'; elements = 'str'; required = $false }
        synchronize_automatically = @{ type = 'bool'; required = $false }
        synchronize_time_of_day = @{ type = 'str'; required = $false }
        number_of_synchronizations_per_day = @{ type = 'int'; required = $false }
        targeting_mode = @{ type = 'str'; required = $false; choices = @('Client', 'Server') }
    }
    supports_check_mode = $true
}

$module = [Ansible.Basic.AnsibleModule]::Create($args, $spec)
$module.result.changed = $false

# The 'upstream_server_name is required when sync_source=upstream_server' rule is validated
# here rather than via the argument spec's 'required_if'. ansible-core 2.16's Ansible.Basic
# throws a NullReferenceException from its required_if check whenever the trigger key
# (sync_source) is omitted (it calls ToString() on the null value); this was fixed in 2.17.
# Validating manually keeps the module working on all supported ansible-core versions (>=2.16).
if (($module.Params.sync_source -eq 'upstream_server') -and
    ([string]::IsNullOrEmpty($module.Params.upstream_server_name))) {
    $module.FailJson("sync_source is upstream_server but all of the following are missing: upstream_server_name")
}

# ---- Connect to the WSUS server ----
$wsus = Connect-WsusServer -module $module `
    -server_name $module.Params.server_name -port $module.Params.port -use_ssl $module.Params.use_ssl

$subscription = $wsus.GetSubscription()

# ---- Reconcile each section in turn. Each function detects whether its section needs a
# ---- change, sets $module.result.changed accordingly, and applies the change unless check
# ---- mode is enabled.
Set-WsusServerConfiguration -module $module -wsus $wsus
Set-WsusSyncSchedule -module $module -subscription $subscription
Set-WsusProductSelection -module $module -wsus $wsus -subscription $subscription
Set-WsusClassificationSelection -module $module -wsus $wsus -subscription $subscription

$module.ExitJson()

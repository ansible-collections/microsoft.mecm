# Copyright: (c) 2026, Ansible Project
# GNU General Public License v3.0+ (see COPYING or https://www.gnu.org/licenses/gpl-3.0.txt)

# NOTE: "return" in powershell does not work as many people expect. Read the PS docs before using it.

Function Connect-WsusServer {
    <#
    .SYNOPSIS
    Connects to a WSUS server using the native WSUS Administration API and returns the server object.

    .DESCRIPTION
    Verifies that the UpdateServices PowerShell module (Get-WsusServer cmdlet) is available, then
    connects to the requested WSUS server. When no server name is provided, the local server is used.

    .PARAMETER module
    The Ansible module object for error reporting.

    .PARAMETER server_name
    The name of the WSUS server to connect to. Defaults to the local server when not provided.

    .PARAMETER port
    The port the WSUS server listens on. Only used when a server name is provided.

    .PARAMETER use_ssl
    Whether to connect using SSL. Only used when a server name is provided.

    .RETURNS
    The IUpdateServer object on success, calls module.FailJson on failure.
    #>
    param (
        [Parameter(Mandatory = $true)][object]$module,
        [Parameter(Mandatory = $false)][string]$server_name,
        [Parameter(Mandatory = $false)][int]$port,
        [Parameter(Mandatory = $false)][bool]$use_ssl = $false
    )

    if ($null -eq (Get-Command -Name Get-WsusServer -ErrorAction SilentlyContinue)) {
        $module.FailJson(
            (
                "The Get-WsusServer cmdlet is not available. You must run this module against a host with the " +
                "WSUS role installed, or with the WSUS Administration tools (RSAT UpdateServices) installed."
            )
        )
    }

    try {
        if ([string]::IsNullOrEmpty($server_name)) {
            $wsus = Get-WsusServer
        }
        else {
            # Get-WsusServer requires PortNumber when a server name is given, so default to the
            # standard WSUS ports (8531 for SSL, 8530 otherwise) when the caller did not supply one.
            if ($port -gt 0) {
                $port_number = $port
            }
            elseif ($use_ssl) {
                $port_number = 8531
            }
            else {
                $port_number = 8530
            }
            $wsus = Get-WsusServer -Name $server_name -PortNumber $port_number -UseSsl:$use_ssl
        }
    }
    catch {
        $module.FailJson("Failed to connect to WSUS server: $($_.Exception.Message)", $_)
    }

    if ($null -eq $wsus) {
        $module.FailJson("Failed to connect to WSUS server: no server object was returned.")
    }

    return $wsus
}


Function Get-WsusEnabledProductTitle {
    <#
    .SYNOPSIS
    Returns the titles of the products (update categories) currently enabled in the subscription.
    #>
    param (
        [Parameter(Mandatory = $true)][object]$subscription
    )

    $titles = @()
    try {
        $categories = $subscription.GetUpdateCategories()
        foreach ($category in $categories) {
            $titles += $category.Title
        }
    }
    catch {
        $null = $_
    }
    return @($titles | Sort-Object -Unique)
}


Function Get-WsusEnabledClassificationTitle {
    <#
    .SYNOPSIS
    Returns the titles of the classifications currently enabled in the subscription.
    #>
    param (
        [Parameter(Mandatory = $true)][object]$subscription
    )

    $titles = @()
    try {
        $classifications = $subscription.GetUpdateClassifications()
        foreach ($classification in $classifications) {
            $titles += $classification.Title
        }
    }
    catch {
        $null = $_
    }
    return @($titles | Sort-Object -Unique)
}


Function ConvertTo-WsusSyncTimeString {
    <#
    .SYNOPSIS
    Formats a TimeSpan (the automatic synchronization time of day) as an HH:mm string.
    #>
    param (
        [Parameter(Mandatory = $true)][AllowNull()]$timeSpan
    )

    if ($null -eq $timeSpan) {
        return ""
    }

    try {
        return ("{0:D2}:{1:D2}" -f $timeSpan.Hours, $timeSpan.Minutes)
    }
    catch {
        return $timeSpan.ToString()
    }
}


Function Format-WsusServerConfigResult {
    <#
    .SYNOPSIS
    Builds the snake_case result dictionary describing a WSUS server's configuration.

    .DESCRIPTION
    Reads the server's configuration, synchronization settings, and subscription, and returns a
    hashtable with all of the values managed and reported by the wsus_server_config modules.

    .PARAMETER wsus
    The IUpdateServer object returned by Connect-WsusServer.
    #>
    param (
        [Parameter(Mandatory = $true)][object]$wsus
    )

    $config = $wsus.GetConfiguration()
    $subscription = $wsus.GetSubscription()

    if ($config.SyncFromMicrosoftUpdate) {
        $sync_source = "microsoft_update"
    }
    else {
        $sync_source = "upstream_server"
    }

    $enabled_languages = @()
    try {
        if (-not $config.AllUpdateLanguagesEnabled) {
            $enabled_languages = @($config.GetEnabledUpdateLanguages())
        }
    }
    catch {
        $null = $_
    }

    return @{
        server_name = $wsus.Name
        port = $wsus.PortNumber
        use_ssl = [bool]$wsus.UseSecureConnection
        sync_source = $sync_source
        upstream_server_name = $config.UpstreamWsusServerName
        upstream_server_port = $config.UpstreamWsusServerPortNumber
        upstream_server_use_ssl = [bool]$config.UpstreamWsusServerUseSsl
        all_update_languages_enabled = [bool]$config.AllUpdateLanguagesEnabled
        enabled_languages = @($enabled_languages)
        targeting_mode = $config.TargetingMode.ToString().ToLower()
        synchronize_automatically = [bool]$subscription.SynchronizeAutomatically
        synchronize_time_of_day = ConvertTo-WsusSyncTimeString -timeSpan $subscription.SynchronizeAutomaticallyTimeOfDay
        number_of_synchronizations_per_day = $subscription.NumberOfSynchronizationsPerDay
        enabled_products = @(Get-WsusEnabledProductTitle -subscription $subscription)
        enabled_classifications = @(Get-WsusEnabledClassificationTitle -subscription $subscription)
    }
}

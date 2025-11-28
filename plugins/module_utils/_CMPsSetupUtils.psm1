# Copyright: (c) 2025, Ansible Project
# GNU General Public License v3.0+ (see COPYING or https://www.gnu.org/licenses/gpl-3.0.txt)

# NOTE: "return" in powershell does not work as many people expect. Read the PS docs before using it.

Function Get-LocalComputerFQDN {
    <#
    This function gets the fully qualified domain name (FQDN) of the server that hosts the site system role.
    If the user provided the computer name, the function will return that value. Otherwise, it will
    calculate the FQDN based on the computer name and domain.
    #>
    $sysinfo = Get-CimInstance Win32_ComputerSystem
    $fqdn = "{0}.{1}" -f $sysinfo.Name, $sysinfo.Domain
    return $fqdn
}


Function Import-CMPsModule {
    param (
        [Parameter(Mandatory = $true)][object]$module
    )

    if ($null -eq (Get-Module -Name ConfigurationManager -ListAvailable)) {
        $module.FailJson(
            (
                "ConfigurationManager PowerShell module is not present. You must connect to a host with the " +
                "ConfigurationManager module installed, or the Configuration Manager Console installed."
            )
        )
    }
    Import-Module -Name ConfigurationManager

}


Function Test-CMSiteDrive {
    param (
        [Parameter(Mandatory = $true)][string]$SiteCode
    )

    if ($null -eq (Get-PSDrive -Name $SiteCode -PSProvider CMSite -ErrorAction SilentlyContinue)) {
        return $false
    }
    return $true
}


Function ConvertTo-SeverityString {
    param (
        [Parameter(Mandatory = $true)][string]$SeverityCode
    )

    switch ($SeverityCode) {
        "3221225472" { return "error" }
        "2147483648" { return "warning" }
        "1073741824" { return "information" }
    }

    return "$SeverityCode"
}


Function Format-ModuleParamAsCmdletArgument {
    # Takes a series of hastable/maps to format module parameters as cmdlet arguments.
    # The direct_mapped_params map is used to map module parameters to cmdlet arguments, one to one.
    # The datetime_params map is used to map module parameter strings to datetime objects.
    # The switch_params map is used to map module parameter booleans to switch values.
    # Each hashtable should have the module parameter name as the key, and the cmdlet argument name as the value.
    param (
        [Parameter(Mandatory = $true)][object]$module,
        [Parameter(Mandatory = $true)][hashtable]$direct_mapped_params,
        [Parameter(Mandatory = $true)][hashtable]$datetime_params,
        [Parameter(Mandatory = $true)][hashtable]$switch_params
    )

    $cmdlet_arguments = @{}
    # map module params that are directly mapped to cmdlet arguments
    foreach ($param in $direct_mapped_params.Keys) {
        $cmdlet_option = $direct_mapped_params.$param
        if ($null -ne $module.Params.$param) {
            $cmdlet_arguments.$cmdlet_option = $module.Params.$param
        }
    }

    # map module params that are datetimes in the cmdlet arguments
    foreach ($param in $datetime_params.Keys) {
        $datetime_param = $datetime_params.$param
        if ($null -ne $module.Params.$param) {
            $cmdlet_arguments.$datetime_param = $(get-date $module.Params.$param)
        }
    }

    # map module params that are switches in the cmdlet arguments
    foreach ($param in $switch_params.Keys) {
        $switch_param = $switch_params.$param
        if ($module.Params.$param -eq $true) {
            $cmdlet_arguments.$switch_param = $true
        }
    }

    return $cmdlet_arguments
}


Function Format-DateTimeAsStringSafely {
    # Format a datetime object as a string, safely. If the datetime object is null, return an empty string.
    # Optionally, provide a format string to use for the datetime object.
    param (
        [Parameter(Mandatory = $true)][AllowNull()]$dateTimeObject,
        [Parameter(Mandatory = $false)][string]$format = "yyyy-MM-dd HH:mm:ss z"
    )

    if ($null -eq $dateTimeObject) {
        return ""
    }

    try {
        return $dateTimeObject.ToString($format)
    }
    catch {
        throw "Failed to format date time object ($dateTimeObject) as string: $($_.Exception.Message)"
    }
}

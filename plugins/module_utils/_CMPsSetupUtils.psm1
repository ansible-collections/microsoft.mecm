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

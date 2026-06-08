#!powershell

# Copyright: (c) 2024, Ansible Community (@ansible-community)
# GNU General Public License v3.0+ (see COPYING or https://www.gnu.org/licenses/gpl-3.0.txt)

#AnsibleRequires -CSharpUtil Ansible.Basic
#AnsibleRequires -PowerShell ..module_utils._CMPsSetupUtils

$spec = @{
    options = @{
        computer_name = @{ required = $false; type = "str" }
        distribution_point = @{ type = "list"; elements = "str" }
        distribution_point_group = @{ type = "list"; elements = "str" }
        package_id = @{ type = "str" }
        site_code = @{ required = $true; type = "str" }
    }
    supports_check_mode = $true
}

$module = [Ansible.Basic.AnsibleModule]::Create($args, $spec)

# ---- Parameters ----
$dp_filter = $module.Params.distribution_point
$dpg_filter = $module.Params.distribution_point_group
$pkg_filter = $module.Params.package_id
$siteCode = $module.Params.site_code

$module.Result.changed = $false


# ---- Import SCCM Module ----
Import-CMPsModule -module $module

# ---- Connect to CMSite ----
Test-CMSiteNameAndConnect -SiteCode $siteCode -Module $module


function Get-DPNameFromNALPath {
    param ([Parameter(Mandatory = $true)][string]$nalPath)
    # NALPath format: ["Display=\\SERVER.FQDN\"]MSWNET:["SMS_SITE=ECO"]\\SERVER.FQDN\
    if ($nalPath -match '\["Display=\\\\([^\\]+)') {
        return $matches[1]
    }
    if ($nalPath -match '\\\\([^\\]+)') {
        return $matches[1]
    }
    return $nalPath
}


function ConvertTo-DPStateString {
    param ([Parameter(Mandatory = $true)][int]$state)
    # SMS_PackageStatusDistPointsSummarizer state values:
    # 0=Installed, 1=InstallPending, 2=InstallRetrying, 3=InstallFailed,
    # 4=RemovalPending, 5=RemovalRetrying, 6=RemovalFailed,
    # 7=UpdatePending, 8=UpdateRetrying, 9=UpdateFailed
    switch ($state) {
        0 { return "Success" }
        { $_ -in 1, 2, 7, 8 } { return "InProgress" }
        { $_ -in 3, 6, 9 } { return "Failed" }
        { $_ -in 4, 5 } { return "RemovalPending" }
        default { return "Unknown" }
    }
}


function Get-StatusFromWMI {
    param (
        [Parameter(Mandatory = $true)][object]$module,
        [Parameter(Mandatory = $true)][string]$siteCode,
        [string[]]$dpNames,
        [string]$packageId
    )
    $namespace = "root\SMS\site_$siteCode"
    $wmiFilter = if ($packageId) { "PackageID='$packageId'" } else { $null }

    try {
        # Query locally - the module already executes on the site server via WinRM,
        # so -ComputerName would cause a double-hop authentication failure.
        $rows = @(Get-CimInstance -Namespace $namespace -ClassName "SMS_PackageStatusDistPointsSummarizer" -Filter $wmiFilter -ErrorAction Stop)
    }
    catch {
        $module.FailJson("Failed to query SMS_PackageStatusDistPointsSummarizer: $($_.Exception.Message)")
    }

    $results = @()
    foreach ($row in $rows) {
        $dpName = Get-DPNameFromNALPath -nalPath $row.ServerNALPath
        if ($dpNames.Count -gt 0 -and ($dpName -notin $dpNames)) {
            continue
        }
        $results += @{
            dp_name = $dpName
            package_id = $row.PackageID
            software_name = ""
            state = ConvertTo-DPStateString -state $row.State
            error = ""
            last_update_date = if ($row.LastCopied) { $row.LastCopied.ToString() } else { "" }
            source_size = 0
        }
    }
    return $results
}


# ---- Get Distribution Status ----
$results = @()

try {
    if ($dpg_filter -or $dp_filter) {
        # Per-DP status requires SMS_PackageStatusDistPointsSummarizer via CIM (queried locally)
        $targetDPNames = @()

        if ($dpg_filter) {
            # Resolve each group to its member DP names
            foreach ($groupName in $dpg_filter) {
                try {
                    $groupDPs = @(Get-CMDistributionPoint -DistributionPointGroupName $groupName -ErrorAction Stop)
                    if (-not $groupDPs) {
                        $module.Warn("Distribution point group '$groupName' has no members or does not exist.")
                        continue
                    }
                    foreach ($gdp in $groupDPs) {
                        $dpName = if ($gdp.NetworkOSPath) {
                            $gdp.NetworkOSPath -replace '^\\\\', ''
                        }
                        elseif ($gdp.NALPath -match '\["Display=\\\\([^\\]+)') {
                            $matches[1]
                        }
                        else { $null }
                        if ($dpName) {
                            $targetDPNames += $dpName
                        }
                    }
                }
                catch {
                    $module.FailJson("Failed to resolve DP group '$groupName': $($_.Exception.Message)")
                }
            }
        }
        elseif ($dp_filter) {
            $targetDPNames = $dp_filter
        }

        # If group resolution produced no DP names, there is nothing to query
        if ($dpg_filter -and $targetDPNames.Count -eq 0) {
            $module.Result.dp_status = @()
            $module.ExitJson()
        }

        $results = Get-StatusFromWMI -module $module -siteCode $siteCode `
            -dpNames $targetDPNames -packageId $pkg_filter
    }
    else {
        # No DP filter - use Get-CMDistributionStatus (returns SMS_ObjectContentExtraInfo, aggregate per package)
        if ($pkg_filter) {
            $statusItems = @(Get-CMDistributionStatus -PackageId $pkg_filter -ErrorAction SilentlyContinue)
        }
        else {
            $statusItems = @(Get-CMDistributionStatus -ErrorAction Stop)
        }
        foreach ($item in $statusItems) {
            $results += @{
                dp_name = ""
                package_id = $item.PackageID
                software_name = $item.SoftwareName
                state = if ($item.NumberSuccess -gt 0) { "Success" } `
                    elseif ($item.NumberErrors -gt 0) { "Failed" } `
                    elseif ($item.NumberInProgress -gt 0) { "InProgress" } `
                    else { "Unknown" }
                error = ""
                last_update_date = $item.LastUpdateDate
                source_size = $item.SourceSize
                number_success = $item.NumberSuccess
                number_errors = $item.NumberErrors
                number_in_progress = $item.NumberInProgress
                number_unknown = $item.NumberUnknown
                targeted = $item.Targeted
            }
        }
    }
}
catch {
    $module.FailJson("Unhandled error querying distribution status: $($_.Exception.Message)")
}

$module.Result.dp_status = $results
$module.ExitJson()

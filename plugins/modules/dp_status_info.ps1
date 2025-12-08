#!powershell

# Copyright: (c) 2024, Ansible Community (@ansible-community)
# GNU General Public License v3.0+ (see COPYING or https://www.gnu.org/licenses/gpl-3.0.txt)

#AnsibleRequires -CSharpUtil Ansible.Basic
#AnsibleRequires -PowerShell ..module_utils._CMPsSetupUtils

$spec = @{
    options = @{
        computer_name = @{ required = $false; type = "str" }
        distribution_point = @{ type = "list"; elements = "str" }
        package_id = @{ type = "str" }
        site_code = @{ required = $true; type = "str" }
    }
    supports_check_mode = $true
}

$module = [Ansible.Basic.AnsibleModule]::Create($args, $spec)

# ---- Parameters ----
$dp_filter = $module.Params.distribution_point
$pkg_filter = $module.Params.package_id
$siteCode = $module.Params.site_code

$module.Result.changed = $false


# ---- Import SCCM Module ----
Import-CMPsModule -module $module

# ---- Connect to CMSite ----
Test-CMSiteNameAndConnect -SiteCode $siteCode -Module $module

# Note: target computer parameter represents the computer to query, which may differ from the site server

# ---- Fetch Distribution Points with filters ----
$dpParams = @{
    ErrorAction = "Stop"
}

try {
    if ($dp_filter) {
        # Query specific DPs when filter is provided
        $allDPs = @()
        foreach ($dpName in $dp_filter) {
            try {
                $dp = Get-CMDistributionPoint -Name $dpName @dpParams
                if ($dp) {
                    $allDPs += $dp
                }
            }
            catch {
                # Continue if specific DP not found, don't fail entire operation
                Write-Verbose "Distribution point $dpName not found - $($_.Exception.Message)"
            }
        }
        $targets = $dp_filter
    }
    else {
        # Query all DPs only when no filter specified
        $allDPs = Get-CMDistributionPoint @dpParams
        $targets = @()
        foreach ($dp in $allDPs) {
            if ($dp.NetworkOSPath) {
                $targets += ($dp.NetworkOSPath -replace '^\\\\', '')
            }
            elseif ($dp.NALPath) {
                # Extract server name from NALPath if NetworkOSPath not available
                if ($dp.NALPath -match '\\\\([^\\]+)') {
                    $targets += $matches[1]
                }
            }
        }
    }
}
catch {
    $module.FailJson("Get-CMDistributionPoint failed: $($_.Exception.Message)")
}

# Continue with empty DPs - will result in empty results array

# ---- Get Distribution Status with efficient single-loop approach ----
$results = @()

try {
    if ($dp_filter) {
        # Filter specified - loop over filtered DPs and pass DP objects directly
        foreach ($dpName in $dp_filter) {
            try {
                $dp = Get-CMDistributionPoint -Name $dpName -ErrorAction SilentlyContinue
                if ($dp) {
                    if ($pkg_filter) {
                        # Specific DP and package combination
                        $status = Get-CMDistributionStatus -InputObject $dp -PackageId $pkg_filter -ErrorAction SilentlyContinue
                    }
                    else {
                        # All packages for this specific DP
                        $status = Get-CMDistributionStatus -InputObject $dp -ErrorAction SilentlyContinue
                    }
                    if ($status) {
                        foreach ($item in $status) {
                            $results += @{
                                dp_name = $dpName
                                package_id = $item.PackageID
                                software_name = $item.SoftwareName
                                state = if ($item.NumberSuccess -gt 0) { "Success" } `
                                    elseif ($item.NumberErrors -gt 0) { "Failed" } `
                                    elseif ($item.NumberInProgress -gt 0) { "InProgress" } `
                                    else { "Unknown" }
                                error = ""
                                last_update_date = $item.LastUpdateDate
                                source_size = $item.SourceSize
                            }
                        }
                    }
                    else {
                        # No status for this DP
                        $results += @{
                            dp_name = $dpName
                            package_id = if ($pkg_filter) { $pkg_filter } else { "N/A" }
                            software_name = ""
                            state = "No Content"
                            error = "No distribution status available"
                            last_update_date = ""
                            source_size = 0
                        }
                    }
                }
            }
            catch {
                # Continue if specific DP not found
                Write-Verbose "Failed to query distribution point - $($_.Exception.Message)"
            }
        }
    }
    else {
        # No DP filter - process all DPs
        if ($allDPs -and $allDPs.Count -gt 0) {
            foreach ($dp in $allDPs) {
                $dpName = if ($dp.NetworkOSPath) {
                    ($dp.NetworkOSPath -replace '^\\\\', '')
                }
                elseif ($dp.NALPath -match '\\\\([^\\]+)') {
                    $matches[1]
                }
                else {
                    "Unknown"
                }

                try {
                    if ($pkg_filter) {
                        # Specific package across all DPs
                        $status = Get-CMDistributionStatus -InputObject $dp -PackageId $pkg_filter -ErrorAction SilentlyContinue
                    }
                    else {
                        # All packages for all DPs
                        $status = Get-CMDistributionStatus -InputObject $dp -ErrorAction SilentlyContinue
                    }
                    if ($status) {
                        foreach ($item in $status) {
                            $results += @{
                                dp_name = $dpName
                                package_id = $item.PackageID
                                software_name = $item.SoftwareName
                                state = if ($item.NumberSuccess -gt 0) { "Success" } `
                                    elseif ($item.NumberErrors -gt 0) { "Failed" } `
                                    elseif ($item.NumberInProgress -gt 0) { "InProgress" } `
                                    else { "Unknown" }
                                error = ""
                                last_update_date = $item.LastUpdateDate
                                source_size = $item.SourceSize
                            }
                        }
                    }
                    else {
                        # No status for this DP
                        $results += @{
                            dp_name = $dpName
                            package_id = if ($pkg_filter) { $pkg_filter } else { "N/A" }
                            software_name = ""
                            state = "No Content"
                            error = "No distribution status available"
                            last_update_date = ""
                            source_size = 0
                        }
                    }
                }
                catch {
                    # Continue if status query fails for this DP
                    Write-Verbose "Failed to query distribution status for DP $dpName - $($_.Exception.Message)"
                }
            }
        }
        # If no DPs found, results will remain empty array
    }
}
catch {
    # If everything fails, return empty results
    $results = @()
}

$module.Result.dp_status = $results
$module.ExitJson()
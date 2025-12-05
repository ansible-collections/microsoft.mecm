#!powershell

# Copyright: (c) 2024, Ansible Community (@ansible-community)
# GNU General Public License v3.0+ (see COPYING or https://www.gnu.org/licenses/gpl-3.0.txt)

#AnsibleRequires -CSharpUtil Ansible.Basic
#AnsibleRequires -PowerShell ..module_utils._CMPsSetupUtils

$spec = @{
    options = @{
        wait_for_completion = @{ required = $false; type = "bool"; default = $true }
        timeout_minutes = @{ required = $false; type = "int"; default = 60 }
        allow_reboot = @{ required = $false; type = "bool"; default = $false }
        reboot_timeout_minutes = @{ required = $false; type = "int"; default = 15 }
        update_ids = @{ required = $false; type = "list"; elements = "str" }
        categories = @{ required = $false; type = "list"; elements = "str" }
    }
    supports_check_mode = $false
}

$module = [Ansible.Basic.AnsibleModule]::Create($args, $spec)

# ---- Parameters ----
$waitForCompletion = $module.Params.wait_for_completion
$timeoutMinutes = $module.Params.timeout_minutes
$allowReboot = $module.Params.allow_reboot
$rebootTimeoutMinutes = $module.Params.reboot_timeout_minutes
$updateIds = $module.Params.update_ids
$categories = $module.Params.categories

$module.Result.changed = $false

# ---- Parameter Validation ----

if ($timeoutMinutes -lt 0) {
    $module.FailJson("timeout_minutes must be greater than or equal to 0")
}

if ($rebootTimeoutMinutes -lt 0) {
    $module.FailJson("reboot_timeout_minutes must be greater than or equal to 0")
}

# ---- Helper Functions ----
Function Test-RebootRequired {
    param()

    # Method 1: Windows Update reboot required
    if (Test-Path -LiteralPath "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired") {
        return $true
    }

    # Method 2: Component-based servicing reboot
    $cbsReboot = Get-ChildItem -LiteralPath "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending" `
        -ErrorAction SilentlyContinue
    if ($cbsReboot) {
        return $true
    }

    # Method 3: File rename operations
    $fileRenames = Get-ItemProperty -LiteralPath "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager" `
        -Name PendingFileRenameOperations -ErrorAction SilentlyContinue
    if ($fileRenames -and $fileRenames.PendingFileRenameOperations) {
        return $true
    }

    return $false
}

Function Test-SCCMClient {
    param([object]$module)

    # Check SCCM service
    $sccmService = Get-Service -Name "CcmExec" -ErrorAction SilentlyContinue
    if (-not $sccmService -or $sccmService.Status -ne "Running") {
        $module.FailJson("SCCM Client service (CcmExec) is not running. This module requires an active SCCM client.")
    }

    # Test CIM namespace access
    try {
        Get-CimInstance -Namespace "root\ccm\ClientSDK" -ClassName "CCM_SoftwareUpdate" -ErrorAction Stop | Out-Null
    }
    catch {
        $module.FailJson("Unable to access SCCM CIM namespace 'root\ccm\ClientSDK'. Error: $($_.Exception.Message)")
    }
}

Function Get-AvailableUpdate {
    param(
        [array]$updateIds = $null,
        [array]$categories = $null,
        [object]$module
    )

    try {
        # Get all available updates (EvaluationState 0 or 1)
        $allUpdates = Get-CimInstance -Namespace "root\ccm\ClientSDK" -ClassName "CCM_SoftwareUpdate" | Where-Object {
            $_.EvaluationState -eq 0 -or $_.EvaluationState -eq 1
        }
        # Filter by specific update IDs if provided
        if ($updateIds -and $updateIds.Count -gt 0) {
            $allUpdates = $allUpdates | Where-Object {
                $_.UpdateID -in $updateIds -or $_.ArticleID -in $updateIds
            }
        }

        # Filter by categories if provided (basic implementation)
        if ($categories -and $categories.Count -gt 0) {
            $allUpdates = $allUpdates | Where-Object {
                $updateName = $_.Name
                $categories | ForEach-Object {
                    if ($updateName -like "*$_*") {
                        return $true
                    }
                }
                return $false
            }
        }

        return $allUpdates
    }
    catch {
        $module.FailJson("Failed to retrieve available updates: $($_.Exception.Message)")
    }
}

Function ConvertTo-SnakeCaseUpdate {
    param([object]$update)

    return @{
        name = $update.Name
        article_id = $update.ArticleID
        update_id = $update.UpdateID
        reboot_required = [bool]$update.RebootRequired
    }
}

Function Get-UpdateEvaluationState {
    param(
        [array]$updatesToMonitor,
        [bool]$checkInProgress = $false
    )

    $currentUpdates = Get-CimInstance -Namespace "root\ccm\ClientSDK" -ClassName "CCM_SoftwareUpdate"
    $installed = @()
    $failed = @()
    $rebootRequired = $false
    $inProgress = $false

    foreach ($originalUpdate in $updatesToMonitor) {
        $currentState = $currentUpdates | Where-Object {
            $_.UpdateID -eq $originalUpdate.UpdateID
        }

        if ($currentState) {
            switch ($currentState.EvaluationState) {
                3 {
                    # Successfully installed
                    $installed += $originalUpdate
                }
                7 {
                    # Installed, pending reboot
                    $installed += $originalUpdate
                    $rebootRequired = $true
                }
                14 {
                    # Installed, pending soft reboot
                    $installed += $originalUpdate
                    $rebootRequired = $true
                }
                { $checkInProgress -and ($_ -in @(6, 11, 12, 13)) } {
                    # Still installing/downloading
                    $inProgress = $true
                }
                default {
                    # Failed or unknown state
                    $failed += $originalUpdate
                }
            }
        }
        else {
            # Update disappeared from WMI - assume failed
            $failed += $originalUpdate
        }
    }

    return @{
        installed = $installed
        failed = $failed
        reboot_required = $rebootRequired
        in_progress = $inProgress
    }
}

Function Test-InstallationTimeout {
    param(
        [DateTime]$startTime,
        [int]$timeoutSeconds
    )

    $elapsed = (Get-Date) - $startTime
    return ($elapsed.TotalSeconds -gt $timeoutSeconds)
}

Function Wait-ForInstallationCompletion {
    param(
        [array]$updatesToMonitor,
        [int]$timeoutSeconds,
        [object]$module
    )

    $startTime = Get-Date
    $pollInterval = 30  # Poll every 30 seconds

    while ($true) {
        # Check for timeout
        if (Test-InstallationTimeout -startTime $startTime -timeoutSeconds $timeoutSeconds) {
            $finalState = Get-UpdateEvaluationState -updatesToMonitor $updatesToMonitor
            return @{
                installed_updates = $finalState.installed
                failed_updates = $finalState.failed
                reboot_required = $finalState.reboot_required -or (Test-RebootRequired)
                timeout_occurred = $true
            }
        }

        # Check current status of all updates
        $currentState = Get-UpdateEvaluationState -updatesToMonitor $updatesToMonitor -checkInProgress $true

        # Check if all updates are done (no longer in progress)
        if (-not $currentState.in_progress) {
            return @{
                installed_updates = $currentState.installed
                failed_updates = $currentState.failed
                reboot_required = $currentState.reboot_required -or (Test-RebootRequired)
                timeout_occurred = $false
            }
        }

        # Sleep before next poll
        Start-Sleep -Seconds $pollInterval
    }
}

# ---- Main Module Logic ----

# Test SCCM Client availability
Test-SCCMClient -module $module

# Get available updates
$availableUpdates = Get-AvailableUpdate -updateIds $updateIds -categories $categories -module $module

if ($availableUpdates.Count -eq 0) {
    $module.Result.installed_updates = @()
    $module.Result.failed_updates = @()
    $module.Result.reboot_required = Test-RebootRequired
    $module.Result.timeout_occurred = $false
    $module.Result.total_updates_processed = 0
    $module.Result.installation_duration = 0
    $module.Result.message = "No updates available for installation"
    $module.ExitJson()
}

# Trigger installation
$startTime = Get-Date
try {
    $managerClass = Get-CimClass -Namespace "root\ccm\ClientSDK" -ClassName "CCM_SoftwareUpdatesManager"
    $installResult = Invoke-CimMethod -CimClass $managerClass -MethodName "InstallUpdates" -Arguments @{ CCMUpdates = $availableUpdates }

    if ($installResult.ReturnValue -ne 0) {
        $module.FailJson("Failed to trigger update installation. Return code: $($installResult.ReturnValue)")
    }

    $module.Result.changed = $true

}
catch {
    $module.FailJson("Error triggering update installation: $($_.Exception.Message)")
}

# Handle completion based on wait_for_completion parameter
if ($waitForCompletion) {
    $timeoutSeconds = $timeoutMinutes * 60
    $completionResult = Wait-ForInstallationCompletion -updatesToMonitor $availableUpdates -timeoutSeconds $timeoutSeconds -module $module

    $module.Result.installed_updates = $completionResult.installed_updates | ForEach-Object { ConvertTo-SnakeCaseUpdate -update $_ }
    $module.Result.failed_updates = $completionResult.failed_updates | ForEach-Object { ConvertTo-SnakeCaseUpdate -update $_ }
    $module.Result.reboot_required = $completionResult.reboot_required
    $module.Result.timeout_occurred = $completionResult.timeout_occurred
    $module.Result.total_updates_processed = $availableUpdates.Count
    $module.Result.installation_duration = [int]((Get-Date) - $startTime).TotalSeconds

    # Handle reboot if required and allowed
    if ($completionResult.reboot_required -and $allowReboot) {
        $module.Result.message = "Updates installed successfully. System reboot initiated."
        try {
            # Use Windows reboot with timeout
            Restart-Computer -Force -Timeout ($rebootTimeoutMinutes * 60)

        }
        catch {
            $module.Result.warnings = @("Failed to initiate reboot: $($_.Exception.Message)")

        }
    }
    elseif ($completionResult.reboot_required) {
        $module.Result.message = "Updates installed successfully. System reboot required but not allowed by allow_reboot parameter."

    }
    else {
        $module.Result.message = "Updates installed successfully. No reboot required."

    }

}
else {
    # Fire-and-forget mode
    $module.Result.installed_updates = @()
    $module.Result.failed_updates = @()
    $module.Result.reboot_required = $false
    $module.Result.timeout_occurred = $false
    $module.Result.total_updates_processed = $availableUpdates.Count
    $module.Result.installation_duration = [int]((Get-Date) - $startTime).TotalSeconds
    $module.Result.message = "Update installation triggered. Use wait_for_completion=true to monitor progress."

}

$module.ExitJson()
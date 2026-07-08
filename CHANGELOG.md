# Microsoft Endpoint Configuration Manager \(MECM\) Ansible Collection\. Release Notes

**Topics**

- <a href="#v2-0-0">v2\.0\.0</a>
    - <a href="#release-summary">Release Summary</a>
    - <a href="#minor-changes">Minor Changes</a>
    - <a href="#breaking-changes--porting-guide">Breaking Changes / Porting Guide</a>
    - <a href="#bugfixes">Bugfixes</a>
- <a href="#v1-0-0">v1\.0\.0</a>
    - <a href="#minor-changes-1">Minor Changes</a>
    - <a href="#breaking-changes--porting-guide-1">Breaking Changes / Porting Guide</a>

<a id="v2-0-0"></a>
## v2\.0\.0

<a id="release-summary"></a>
### Release Summary

Expansion of Microsoft\.MECM for Unified Endpoint Management

<a id="minor-changes"></a>
### Minor Changes

* application \- Add new module to create\, update\, or delete applications in Microsoft Endpoint Configuration Manager \(MECM\)\.
* application\_deployment\_type \- Add new module to add or remove MSI and Script deployment types on MECM applications\.
* application\_deployment\_type\_info \- Add new module to retrieve deployment type information from MECM applications\.
* application\_deployments \- Add new module to create\, update\, or delete application deployments in MECM\. Supports C\(deploy\_action\) \(Install/Uninstall\) and C\(deploy\_purpose\) \(Required/Available\)\, optional content distribution via a distribution point group\.
* application\_deployments\_info \- Add new info module to retrieve application deployment information from MECM\. Supports filtering site\-wide\, by application name\, or by both application name and collection name\.
* application\_info \- Add new module to retrieve application information from MECM including metadata\, ownership\, and Software Center display properties\.
* boundaries \- Add new module to create\, rename\, or delete site boundaries in Microsoft Endpoint Configuration Manager \(MECM\) with full idempotency support for IPSubnet\, ADSite\, IPV6Prefix\, IPRange\, and VPN boundary types\.
* boundaries\, boundaries\_info \- Extract shared C\(Format\-BoundaryResult\) and C\(ConvertTo\-BoundaryTypeInt\) into a new C\(module\_utils/\_BoundaryUtils\.psm1\) to eliminate code duplication\.
* boundaries\_info \- Add new module to retrieve site boundary information from MECM\, with optional filtering by boundary type or display name\.
* client\_settings \- Add new module to create\, update\, and delete MECM client settings of type device or user\, with support for priority\, description\, and custom settings configuration\.
* client\_settings\, client\_settings\_info \- Extract shared C\(Format\-ClientSettingResult\) and C\(ConvertTo\-ClientSettingTypeString\) into a new C\(module\_utils/\_ClientSettingUtils\.psm1\) to eliminate code duplication\.
* client\_settings\_info \- Add new module to retrieve MECM client settings information\, with optional filtering by name\.
* device\_collection \- Add new module to create\, update\, or delete Device Collections in MECM\, including support for manual\, periodic\, continuous\, and both refresh types with configurable schedules\, and management of query and direct membership rules via C\(device\_collection\_query\_rules\) and C\(device\_collection\_direct\_rules\)\.
* device\_collection\, device\_collection\_info \- Extract shared C\(ConvertFrom\-CMRefreshType\) into a new C\(module\_utils/\_DeviceCollectionUtils\.psm1\) to eliminate code duplication\.
* device\_collection\_info \- Add new module to retrieve Device Collection information from MECM\, including collection properties and all configured query and direct membership rules\.
* distribution\_point\_group \- Add new module to create\, update\, or delete Distribution Point Groups in MECM\, including idempotent membership reconciliation \(add/remove DPs\) and group rename support via C\(new\_name\)\.
* distribution\_point\_group\_info \- Add new module to retrieve Distribution Point Group information from MECM\, including member distribution point FQDNs for each group\.
* maintenance\_windows \- Add new module to create\, update\, or delete Maintenance Windows on a Device Collection in MECM\, supporting None and Daily recurrence schedules\, all three C\(apply\_to\) types\, and full idempotency\.
* maintenance\_windows\, maintenance\_windows\_info \- Extract shared C\(Format\-MaintenanceWindowResult\) and C\(ConvertTo\-ServiceWindowTypeInt\) into a new C\(module\_utils/\_MaintenanceWindowUtils\.psm1\) to eliminate code duplication\.
* maintenance\_windows\_info \- Add new module to retrieve Maintenance Window information for a Device Collection in MECM\, returning all windows or a single named window with its schedule token\, duration\, C\(apply\_to\) type\, and enabled state\.
* software\_update\_adr \- Add new module to create\, update\, or delete Software Update Auto Deployment Rules \(ADRs\) in MECM With full idempotency across filters\, deployment options\, run type\, and schedule\.
* software\_update\_adr\_info \- Add new module to retrieve Software Update Auto Deployment Rule information from MECM\, Including enabled state\, run type\, and collection assignment\.
* task\_sequence \- Add new module to create\, import\, update\, or delete a Task Sequence in MECM\, supporting C\(create\_method\=import\) and C\(create\_method\=custom\)
* task\_sequence\_info \- Add new info module to retrieve Task Sequence information from MECM\, supporting system\-wide listing or filtering by name\.

<a id="breaking-changes--porting-guide"></a>
### Breaking Changes / Porting Guide

* install\_updates \- Remove O\(allow\_reboot\) and O\(reboot\_timeout\_minutes\) parameters\. The module no longer reboots the system itself\; instead it returns RV\(reboot\_required\=true\) and the caller is expected to handle the reboot using M\(ansible\.windows\.win\_reboot\)\. This avoids dropping the WinRM connection mid\-task before results are returned\.

<a id="bugfixes"></a>
### Bugfixes

* device\_collection \- Remove incorrect C\(default\: Manual\) documentation field from C\(refresh\_type\)\; the parameter has no spec\-level default and the conditional creation behaviour is already described in the option description\.
* dp\_status\_info \- Fix C\(distribution\_point\) and C\(distribution\_point\_group\) filters returning no results\; per\-DP status is now queried via C\(SMS\_PackageStatusDistPointsSummarizer\) over local CIM\, which works correctly for group\-distributed content and avoids WinRM double\-hop authentication failures\.
* dp\_status\_info \- Fix C\(distribution\_point\_group\) with a non\-existent or empty group returning all records instead of an empty list\.
* dp\_status\_info \- Fix empty results for package\-only and site\-wide queries by replacing broken C\(Get\-CMDistributionStatus \-InputObject \$dp\) calls with C\(\-PackageId\) and bare invocations that match how the cmdlet is designed to be used\.
* install\_updates \- Fix C\(Unable to cast object of type \'Microsoft\.Management\.Infrastructure\.Native\.InstanceHandle\' to type \'System\.Collections\.IList\'\) error when calling C\(CCM\_SoftwareUpdatesManager\.InstallUpdates\)\. The C\(CCMUpdates\) argument is now explicitly cast to C\(\[CimInstance\[\]\]\) so the CIM infrastructure marshals the collection as a typed array that satisfies the IList contract expected by the native WMI method\.
* install\_updates \- Fix RV\(installed\_updates\) and RV\(failed\_updates\) returning V\(null\) or a bare dict instead of a list\. C\(ForEach\-Object\) over an empty array returns C\(null\) in PowerShell\; results are now wrapped in C\(\@\(\)\) to guarantee a JSON array is always returned\.
* install\_updates \- Fix RV\(installed\_updates\[\]\.reboot\_required\) always reporting V\(false\) regardless of post\-installation state\. The C\(RebootRequired\) WMI property is unreliable after installation\; the field is now derived from C\(EvaluationState\) directly\: states C\(8\) \(PendingSoftReboot\)\, C\(9\) \(PendingHardReboot\)\, and C\(10\) \(WaitReboot\) map to V\(true\)\, all other terminal states map to V\(false\)\.
* install\_updates \- Fix RV\(reboot\_required\) returning V\(true\) on idempotent re\-runs where V\(changed\=false\)\. When no updates are available the module now returns RV\(reboot\_required\=false\) instead of checking the Windows registry\, keeping the return value scoped to what the current invocation actually did\.
* install\_updates \- Fix RV\(total\_updates\_installed\) returning V\(null\) when only one update matches the filter\. C\(Where\-Object\) returns a scalar C\(CimInstance\) \(not an array\) for single\-item results\; C\(Get\-AvailableUpdate\) now wraps its return value in C\(\@\(\)\) and filters nulls to ensure C\(\.Count\) always resolves correctly\.
* install\_updates \- Fix module returning immediately without waiting when O\(wait\_for\_completion\=true\)\. Incorrect C\(EvaluationState\) mappings caused states such as C\(7\) \(Installing\) and C\(0/1\) \(Available\, seen immediately after triggering\) to be classified as terminal failures\, setting C\(in\_progress\=false\) and exiting the polling loop on the first iteration\. All non\-terminal states now correctly set C\(in\_progress\=true\) so the loop waits until installation completes\.
* maintenance\_windows\_info \- Fix C\(name\) filter returning all maintenance windows instead of the named one by switching from the C\(\-Name\) alias to the canonical C\(\-MaintenanceWindowName\) parameter and adding C\(\-DisableWildcardHandling\) to prevent wildcard interpretation of the window name\. Same fix applied to the three lookup calls in C\(maintenance\_windows\)\.

<a id="v1-0-0"></a>
## v1\.0\.0

<a id="minor-changes-1"></a>
### Minor Changes

* Add client\_action module
* Add site\_ps\_drive module
* Add site\_status\_message\_info module
* Add software\_update\_deployment module
* Add software\_update\_deployment\_info module
* Add software\_update\_group module
* Add software\_update\_group\_info module
* Add software\_update\_group\_membership module
* Add software\_update\_info module
* backups\_status\_info \- Add new module to retrieve SCCM site backup status information including task configuration\, schedule\, and execution history\.
* dp\_status\_info \- Add new module to retrieve distribution point status information from SCCM\.
* install\_updates \- Add new module to orchestrate software update installation on SCCM clients with intelligent progress monitoring\, timeout handling\, and reboot management\.
* wsus\_sync\_status\_info \- Add new module to retrieve WSUS synchronization status information from SCCM software update points with last sync time\, status\, and error reporting\.

<a id="breaking-changes--porting-guide-1"></a>
### Breaking Changes / Porting Guide

* backups\_status\_info \- Changed parameter from <code>site\_name</code> to <code>site\_code</code> for consistency across modules
* dp\_status\_info \- Added required <code>site\_code</code> parameter
* wsus\_sync\_status\_info \- Added required <code>site\_code</code> parameter

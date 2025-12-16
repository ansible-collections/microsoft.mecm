# CHANGE THIS IN changelogs/config\.yaml\! Release Notes

**Topics**

- <a href="#v1-0-0">v1\.0\.0</a>
    - <a href="#minor-changes">Minor Changes</a>
    - <a href="#breaking-changes--porting-guide">Breaking Changes / Porting Guide</a>

<a id="v1-0-0"></a>
## v1\.0\.0

<a id="minor-changes"></a>
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

<a id="breaking-changes--porting-guide"></a>
### Breaking Changes / Porting Guide

* backups\_status\_info \- Changed parameter from <code>site\_name</code> to <code>site\_code</code> for consistency across modules
* dp\_status\_info \- Added required <code>site\_code</code> parameter
* wsus\_sync\_status\_info \- Added required <code>site\_code</code> parameter

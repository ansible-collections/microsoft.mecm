====================================================
CHANGE THIS IN changelogs/config.yaml! Release Notes
====================================================

.. contents:: Topics

v1.0.0
======

Minor Changes
-------------

- Add client_action module
- Add site_ps_drive module
- Add site_status_message_info module
- Add software_update_deployment module
- Add software_update_deployment_info module
- Add software_update_group module
- Add software_update_group_info module
- Add software_update_group_membership module
- Add software_update_info module
- backups_status_info - Add new module to retrieve SCCM site backup status information including task configuration, schedule, and execution history.
- dp_status_info - Add new module to retrieve distribution point status information from SCCM.
- install_updates - Add new module to orchestrate software update installation on SCCM clients with intelligent progress monitoring, timeout handling, and reboot management.
- wsus_sync_status_info - Add new module to retrieve WSUS synchronization status information from SCCM software update points with last sync time, status, and error reporting.

Breaking Changes / Porting Guide
--------------------------------

- backups_status_info - Changed parameter from ``site_name`` to ``site_code`` for consistency across modules
- dp_status_info - Added required ``site_code`` parameter
- wsus_sync_status_info - Added required ``site_code`` parameter

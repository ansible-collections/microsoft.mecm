# Microsoft MECM Collection for Ansible
[![CI](https://github.com/ansible-collections/microsoft.mecm/workflows/CI/badge.svg?event=push)](https://github.com/ansible-collections/microsoft.mecm/actions) [![Codecov](https://img.shields.io/codecov/c/github/ansible-collections/microsoft.mecm)](https://codecov.io/gh/ansible-collections/microsoft.mecm)

This collection provides Ansible modules and plugins to manage Microsoft System Center Configuration Manager (MECM/SCCM/ConfigMgr) infrastructure through automation.

## Description

The `microsoft.mecm` collection provides a comprehensive set of Ansible modules
for automating Microsoft System Center Configuration Manager (MECM/SCCM/ConfigMgr)
environments on Windows. It is designed for IT administrators and infrastructure
engineers who need to manage MECM objects - such as applications, device collections,
software updates, maintenance windows, as well as managing client Software Center update installations - through repeatable, idempotent Ansible playbooks.
By leveraging this collection, teams can eliminate manual console-based workflows,
enforce consistent configuration across their MECM hierarchy, and integrate
Configuration Manager management into broader infrastructure-as-code pipelines.

## Requirements

- **Ansible**: `>= 2.16.0`
- **Python**: `>= 3.12`
- **Target OS**: Windows with Microsoft MECM/SCCM/ConfigMgr installed and the MECM PowerShell console/module available
- **WinRM**: Windows Remote Management (WinRM) must be configured and reachable on the target host
- **Python package** (control node): `pywinrm` — required for WinRM connectivity

## Installation

Before using this collection, you need to install it with the Ansible Galaxy command-line tool:
```bash
ansible-galaxy collection install ansible.microsoft.mecm
```

You can also include it in a `requirements.yml` file and install it with `ansible-galaxy collection install -r requirements.yml`, using the format:
```yaml
---
collections:
  - name: ansible.microsoft.mecm
```

Note that if you install the collection from Ansible Galaxy, it will not be upgraded automatically when you upgrade the `ansible` package. To upgrade the collection to the latest available version, run the following command:
```bash
ansible-galaxy collection install ansible.microsoft.mecm --upgrade
```

You can also install a specific version of the collection, for example, if you need to downgrade when something is broken in the latest version (please report an issue in this repository). Use the following syntax to install version `0.1.0`:

```bash
ansible-galaxy collection install ansible.microsoft.mecm:==0.1.0
```

See [using Ansible collections](https://docs.ansible.com/ansible/devel/user_guide/collections_using.html) for more details.

## Use Cases

The `microsoft.mecm` collection is designed to automate the most common day-to-day tasks
performed by MECM administrators — from managing device collections and scheduling maintenance
windows to deploying operating systems via task sequences.
The examples below represent real operational workflows that can be integrated
directly into your infrastructure-as-code pipelines.

### 1. Automated Software Update Patching

Install all available security updates on SCCM-managed Windows clients and safely reboot if required.

```yaml
- name: Patch Windows clients and reboot if needed
  hosts: windows_servers
  tasks:
    - name: Install security updates
      microsoft.mecm.install_updates:
        categories:
          - Security
        wait_for_completion: true
        timeout_minutes: 90
      register: patch_result

    - name: Reboot if required
      ansible.windows.win_reboot:
        reboot_timeout: 600
      when: patch_result.reboot_required
```

---

### 2. Device Collection Management

Create and maintain device collections scoped by WQL query expressions, ensuring consistent group membership across the MECM hierarchy.

```yaml
- name: Manage device collections
  hosts: mecm_server
  tasks:
    - name: Create a collection of all production servers
      microsoft.mecm.device_collection:
        site_code: "ECO"
        name: "Servers - Production"
        limiting_collection_name: "All Systems"
        refresh_type: Periodic
        schedule_recur_interval: Days
        schedule_recur_count: 1
        schedule_start: "2026-01-01 06:00"
        state: present
        device_collection_query_rules:
          - rule_name: "Production Servers"
            query_expression: >
              select * from SMS_R_System
              where SMS_R_System.OperatingSystemNameandVersion like '%Server%'
```

---

### 3. Maintenance Window Scheduling

Enforce recurring maintenance windows on collections to control when software updates and task sequences are permitted to run.

```yaml
- name: Configure patching maintenance windows
  hosts: mecm_server
  tasks:
    - name: Set nightly software-update window for Tier-1 servers
      microsoft.mecm.maintenance_windows:
        site_code: "ECO"
        device_collection_name: "Servers - Tier 1"
        name: "Nightly SU Window"
        apply_to: SoftwareUpdatesOnly
        sched_recur_type: Daily
        sched_recur_count: 1
        sched_duration_count: 4
        sched_duration_interval: Hours
        sched_start: "01/01/2026 02:00:00"
        state: present
```

---

## Testing

All modules in this collection are validated through automated integration tests that run
against a live Microsoft MECM environment.

### Ansible Versions Tested

| Ansible Version | Python Version |
|---|---|
| `stable-2.16` | 3.12 |
| `stable-2.17` | 3.12 |
| `stable-2.18` | 3.12 |
| `stable-2.19` | 3.12 |
| `devel` | 3.13 |

### Integration Test Coverage

Each module has a dedicated integration test target under `tests/integration/targets/`.

### Static Analysis

All playbooks and module documentation are linted with `ansible-lint v6.22.0`.

### Known Exceptions and Workarounds

- **Reboot handling**: The `install_updates` module reports `reboot_required` but does **not**
  trigger a reboot itself. Use `ansible.windows.win_reboot` in your playbook to handle reboots
  safely after update installation.
- **Fire-and-forget installs**: When `install_updates` is called with `wait_for_completion: false`,
  no installation results are returned. Verify completion through other means (e.g., re-running
  with `wait_for_completion: true` or checking the MECM console).
- **Task sequence import idempotency**: When using `create_method: import`, the module always
  reports `changed: true` because MECM overwrites the task sequence on every import regardless
  of whether the content has changed.
- **Device collection limiting scope**: The `device_collection` module requires the
  `limiting_collection_name` to already exist in MECM before the module runs.
- **Maintenance window target**: The `maintenance_windows` module requires the target
  `device_collection_name` to already exist; it will fail if the collection is absent.

## Contributing to this collection

The content of this collection is made by people like you, a community of individuals collaborating on making the world better through developing automation software.

We are actively accepting new contributors and all types of contributions are very welcome.

Don't know how to start? Refer to the [Ansible community guide](https://docs.ansible.com/ansible/devel/community/index.html)!

Want to submit code changes? Take a look at the [Quick-start development guide](https://docs.ansible.com/ansible/devel/community/create_pr_quick_start.html).

We also use the following guidelines:

* [Collection review checklist](https://docs.ansible.com/ansible/devel/community/collection_contributors/collection_reviewing.html)
* [Ansible development guide](https://docs.ansible.com/ansible/devel/dev_guide/index.html)
* [Ansible collection development guide](https://docs.ansible.com/ansible/devel/dev_guide/developing_collections.html#contributing-to-collections)

## Support

As a Red Hat Ansible [Certified Content](https://catalog.redhat.com/software/search?target_platforms=Red%20Hat%20Ansible%20Automation%20Platform), this collection is entitled to [support](https://access.redhat.com/support/) through [Ansible Automation Platform](https://www.redhat.com/en/technologies/management/ansible) (AAP) through the Red Hat Ansible team.

If a support case cannot be opened with Red Hat or the collection has been obtained either from [Galaxy](https://galaxy.ansible.com/ui/) or [GitHub](https://github.com/ansible-collections/microsoft.mecm), you can open a GitHub issue on this repo but this has no guarantee of support or timeframes for a response.

## Release notes and Roadmap

See the [changelog](https://github.com/ansible-collections/microsoft.mecm/tree/main/CHANGELOG.rst).

## Roadmap


## Our mission

At the Microsoft MECM collection, our mission is to produce and maintain simple, flexible,
and powerful open-source software tailored to Microsoft Configuration Manager automation and management.

We welcome members from all skill levels to participate actively in our open, inclusive, and vibrant community.
Whether you are an expert or just beginning your journey with Ansible and Microsoft MECM,
you are encouraged to contribute, share insights, and collaborate with fellow enthusiasts!

## Code of Conduct

We follow the [Ansible Code of Conduct](https://docs.ansible.com/ansible/devel/community/code_of_conduct.html) in all our interactions within this project.

If you encounter abusive behavior, please refer to the [policy violations](https://docs.ansible.com/ansible/devel/community/code_of_conduct.html#policy-violations) section of the Code for information on how to raise a complaint.

## Communication


* Join the Ansible forum:
  * [Get Help](https://forum.ansible.com/c/help/6): get help or help others. Please add appropriate tags if you start new discussions, for example the `microsoft` and `mecm` tags.
  * [Posts tagged with 'microsoft'](https://forum.ansible.com/tag/microsoft): subscribe to participate in Microsoft-related conversations.
  * [Posts tagged with 'mecm'](https://forum.ansible.com/tag/mecm): subscribe to participate in MECM-related conversations.
  * [Social Spaces](https://forum.ansible.com/c/chat/4): gather and interact with fellow enthusiasts.
  * [News & Announcements](https://forum.ansible.com/c/news/5): track project-wide announcements including social events. The [Bullhorn newsletter](https://docs.ansible.com/ansible/devel/community/communication.html#the-bullhorn), which is used to announce releases and important changes, can also be found here.

For more information about communication, see the [Ansible communication guide](https://docs.ansible.com/ansible/devel/community/communication.html).



## Collection maintenance

The current maintainers are listed in the [MAINTAINERS](MAINTAINERS) file. If you have questions or need help, feel free to mention them in the proposals.

To learn how to maintain/become a maintainer of this collection, refer to the [Maintainer guidelines](https://docs.ansible.com/ansible/devel/community/maintainers.html).

It is necessary for maintainers of this collection to be subscribed to:

* The collection itself (the `Watch` button -> `All Activity` in the upper right corner of the repository's homepage).
* The [news-for-maintainers repository](https://github.com/ansible-collections/news-for-maintainers).

They also should be subscribed to Ansible's [The Bullhorn newsletter](https://docs.ansible.com/ansible/devel/community/communication.html#the-bullhorn).

## Governance

The process of decision making in this collection is based on discussing and finding consensus among participants.
Every voice is important. If you have something on your mind, create an issue or dedicated discussion and let's discuss it!

## Tested with Ansible


## External requirements


### Supported connections

## Included content


## Using this collection

## Related information

- [Ansible user guide](https://docs.ansible.com/ansible/devel/user_guide/index.html)
- [Ansible developer guide](https://docs.ansible.com/ansible/devel/dev_guide/index.html)
- [Ansible collections requirements](https://docs.ansible.com/ansible/devel/community/collection_contributors/collection_requirements.html)
- [Ansible community Code of Conduct](https://docs.ansible.com/ansible/devel/community/code_of_conduct.html)
- [The Bullhorn (the Ansible contributor newsletter)](https://docs.ansible.com/ansible/devel/community/communication.html#the-bullhorn)
- [Important announcements for maintainers](https://github.com/ansible-collections/news-for-maintainers)

## License Information

GNU General Public License v3.0 or later.

See [LICENSE](https://www.gnu.org/licenses/gpl-3.0.txt) to see the full text.

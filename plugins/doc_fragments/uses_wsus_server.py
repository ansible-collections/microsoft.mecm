# Copyright (c) 2025 Ansible Project
# GNU General Public License v3.0+ (see COPYING or https://www.gnu.org/licenses/gpl-3.0.txt)

from __future__ import (absolute_import, division, print_function)
__metaclass__ = type


class ModuleDocFragment:
    """Common documentation for modules that connect to a WSUS server using the native WSUS API."""

    DOCUMENTATION = r"""
notes:
    - This module uses the native WSUS Administration API (C(Get-WsusServer)).
      The target host must have the WSUS role installed, or the WSUS Administration
      tools (RSAT UpdateServices) installed.
    - This module does not use the Configuration Manager PowerShell module and does
      not require a site code.

author:
    - Ansible Ecosystem Engineering team (@eco-ansible-content)

requirements:
    - WSUS Administration API (the UpdateServices PowerShell module, C(Get-WsusServer) cmdlet)
    - Administrative access to the WSUS server

options:
    server_name:
        description:
            - The name of the WSUS server to connect to.
            - When omitted, the module connects to the WSUS server on the local host.
        type: str
        required: false
    port:
        description:
            - The port that the WSUS server listens on.
            - Only used when O(server_name) is provided.
            - If the port is not provided 8530 will be used for non-SSL connections
              while 8531 is used for SSL connections
        type: int
        required: false
    use_ssl:
        description:
            - Whether to connect to the WSUS server using SSL.
            - Only used when O(server_name) is provided.
        type: bool
        required: false
        default: false
"""

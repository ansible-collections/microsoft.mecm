# -*- coding: utf-8 -*-

# Copyright (c) 2020 Ansible Project
# GNU General Public License v3.0+ (see COPYING or https://www.gnu.org/licenses/gpl-3.0.txt)

from __future__ import (absolute_import, division, print_function)
__metaclass__ = type


class ModuleDocFragment:

    # Common documentation for modules that use the Configuration Manager PowerShell module
    DOCUMENTATION = r'''
notes:
    - This module requires the Configuration Manager PowerShell module to be installed on the target host.
      You can install it directly, or install the Configuration Manager Console on the target host.
    - This module requires a PS drive for the CM site being managed. You can use the
      m(microsoft.mecm.site_ps_drive) module to create the PS drive.

options:
    site_code:
        description:
            - The site code of the site for which you want to perform the action.
        type: str
        required: true
'''

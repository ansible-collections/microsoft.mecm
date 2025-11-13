#!/usr/bin/python
# -*- coding: utf-8 -*-

# Copyright: (c) 2017, Noah Sparks <nsparks@outlook.com>
# Copyright: (c) 2017, Ansible Project
# GNU General Public License v3.0+ (see COPYING or https://www.gnu.org/licenses/gpl-3.0.txt)

DOCUMENTATION = r'''
---
module: site_ps_drive
short_description: Manage the PS drive for a Configuration Manager site
description:
    - This module creates or removes the PS drive for a Configuration Manager site.
    - A PS drive is required for many Configuration Manager cmdlets. This module can be used to ensure the PS drive is present
      before running other modules.

options:
    site_code:
        description:
            - The site code of the site for which you want to create or remove the PS drive.
        type: str
        required: true
    state:
        description:
            - Whether to create or remove the PS drive.
        type: str
        choices: [present, absent]
        required: false
        default: present

author:
    - Ansible Cloud Team (@ansible-collections)
'''


EXAMPLES = r'''
# Creates 'XYZ:\' drive
- name: Create the PS drive for the site "XYZ" if it doesn't exist
  microsoft.mecm.site_ps_drive:
    site_code: XYZ
    state: present

- name: Remove the PS drive for the site "XYZ" if it exists
  microsoft.mecm.site_ps_drive:
    site_code: XYZ
    state: absent
'''

RETURN = r'''
'''

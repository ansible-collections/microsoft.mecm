# Copyright: (c) 2026, Ansible Project
# GNU General Public License v3.0+ (see COPYING or https://www.gnu.org/licenses/gpl-3.0.txt)

# NOTE: "return" in powershell does not work as many people expect. Read the PS docs before using it.


function ConvertFrom-CMRefreshType {
    param ([int]$value)
    switch ($value) {
        1 { return 'Manual' }
        2 { return 'Periodic' }
        4 { return 'Continuous' }
        6 { return 'Both' }
        default { return "Unknown ($value)" }
    }
}

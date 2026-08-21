#!powershell

# Copyright: (c) 2025, Ansible Project
# GNU General Public License v3.0+ (see COPYING or https://www.gnu.org/licenses/gpl-3.0.txt)

#AnsibleRequires -CSharpUtil Ansible.Basic
#AnsibleRequires -PowerShell ..module_utils._WsusUtils

$spec = @{
    options = @{
        server_name = @{ type = 'str'; required = $false }
        port = @{ type = 'int'; required = $false }
        use_ssl = @{ type = 'bool'; required = $false; default = $false }
    }
    supports_check_mode = $true
}

$module = [Ansible.Basic.AnsibleModule]::Create($args, $spec)
$module.result.changed = $false
$module.result.wsus_server_config = @{}

# ---- Parameters ----
$server_name = $module.Params.server_name
$port = $module.Params.port
$use_ssl = $module.Params.use_ssl

# ---- Connect to the WSUS server ----
$wsus = Connect-WsusServer -module $module -server_name $server_name -port $port -use_ssl $use_ssl

# ---- Read and format the configuration ----
try {
    $module.result.wsus_server_config = Format-WsusServerConfigResult -wsus $wsus
}
catch {
    $module.FailJson("Failed to read WSUS server configuration: $($_.Exception.Message)", $_)
}

$module.ExitJson()

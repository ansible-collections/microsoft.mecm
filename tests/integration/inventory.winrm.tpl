[windows]
sccm_test_host ansible_host=$MECM_HOSTNAME

[windows:vars]
ansible_user=$MECM_USERNAME
ansible_password=$MECM_PASSWORD
ansible_connection=winrm
ansible_winrm_transport=ntlm
ansible_winrm_server_cert_validation=ignore

# support winrm connection tests (temporary solution, does not support testing enable/disable of pipelining)
[winrm:children]
windows

# support tests that target testhost
[testhost:children]
windows

# Development

## Running tests

To run sanity tests, simply run `make sanity` in the root of this repo.

To run integration tests:
1. Create a windows test host with MECM installed on it, if one does not already exist in your environment. Ensure winrm with ntlm is enabled

2. Export the following bash vars (update the values for your environment)
MECM_HOSTNAME=192.168.1.1
MECM_USERNAME=Administrator@contoso.com
MECM_PASSWORD=MyPassword!

3. Run `make integration`

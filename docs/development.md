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

## Release

To release a new version:

1. Checkout a clean version of main. Make sure to remove any untracked files

2. Check the version in galaxy.yml and determine the next release version.

3. Create a new branch called 'release/x.x.x' with your version

4. Update version in galaxy.yml

5. Run `antsibull-changelog release`. You can install antsibull-changelog using pip

6. Verify changelog fragments were removed

7. Commit with message 'release x.x.x'

# setup commands
.PHONY: upgrade-collections
upgrade-collections:
	ansible-galaxy collection install --upgrade -p ~/.ansible/collections .

.PHONY: install-integration-reqs
install-integration-reqs:
	pip install -r tests/integration/requirements.txt;

tests/integration/inventory.winrm:
	chmod +x ./tests/integration/generate_inventory.sh; \
	./tests/integration/generate_inventory.sh

# test commands
.PHONY: sanity
sanity: upgrade-collections
	cd ~/.ansible/collections/ansible_collections/microsoft/mecm; \
	ansible-test sanity -v --color --coverage --junit --docker default

.PHONY: integration
integration: tests/integration/inventory.winrm install-integration-reqs upgrade-collections
	cp tests/integration/inventory.winrm ~/.ansible/collections/ansible_collections/microsoft/mecm/tests/integration/inventory.winrm; \
	cd ~/.ansible/collections/ansible_collections/microsoft/mecm; \
	ansible --version; \
	ansible-test --version; \
	ANSIBLE_COLLECTIONS_PATH=~/.ansible/collections/ansible_collections ansible-galaxy collection list; \
	ANSIBLE_ROLES_PATH=~/.ansible/collections/ansible_collections/microsoft/mecm/tests/integration/targets \
		ANSIBLE_COLLECTIONS_PATH=~/.ansible/collections/ansible_collections \
		ansible-test windows-integration $(CLI_ARGS);

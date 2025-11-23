ANSIBLE_COLLECTIONS_PATH ?= ~/.ansible/collections

# setup commands
.PHONY: upgrade-collections
upgrade-collections:
	ansible-galaxy collection install --upgrade -p $(ANSIBLE_COLLECTIONS_PATH) .

.PHONY: install-integration-reqs
install-integration-reqs:
	pip install -r tests/integration/requirements.txt; \
	ansible-galaxy collection install --upgrade -r tests/integration/requirements.yml -p $(ANSIBLE_COLLECTIONS_PATH)

tests/integration/inventory.winrm:
	chmod +x ./tests/integration/generate_inventory.sh; \
	./tests/integration/generate_inventory.sh

# test commands
.PHONY: sanity
sanity: upgrade-collections
	cd $(ANSIBLE_COLLECTIONS_PATH)/ansible_collections/microsoft/mecm; \
	ansible-test sanity -v --color --coverage --junit --docker default

.PHONY: integration
integration: tests/integration/inventory.winrm install-integration-reqs upgrade-collections
	cp tests/integration/inventory.winrm $(ANSIBLE_COLLECTIONS_PATH)/ansible_collections/microsoft/mecm/tests/integration/inventory.winrm; \
	cd $(ANSIBLE_COLLECTIONS_PATH)/ansible_collections/microsoft/mecm; \
	ansible --version; \
	ansible-test --version; \
	ANSIBLE_COLLECTIONS_PATH=$(ANSIBLE_COLLECTIONS_PATH)/ansible_collections ansible-galaxy collection list; \
	ANSIBLE_ROLES_PATH=$(ANSIBLE_COLLECTIONS_PATH)/ansible_collections/microsoft/mecm/tests/integration/targets \
		ANSIBLE_COLLECTIONS_PATH=$(ANSIBLE_COLLECTIONS_PATH)/ansible_collections \
		ansible-test windows-integration $(CLI_ARGS);
.PHONY: lint check deploy

INVENTORY ?= inventories/dev/hosts.ini
PLAYBOOK ?= site.yml

lint:
	ansible-lint $(PLAYBOOK)

check:
	ansible-playbook -i $(INVENTORY) $(PLAYBOOK) --syntax-check

deploy:
	ansible-playbook -i $(INVENTORY) $(PLAYBOOK) --ask-vault-pass

.PHONY: venv lint check ping deploy

INVENTORY ?= inventories/host.yml
PLAYBOOK ?= site.yml
VENV ?= .venv
PYTHON ?= python3
PIP := $(VENV)/bin/pip
VENV_ACTIVATE := . $(VENV)/bin/activate

$(VENV)/bin/activate: requirements.txt
	$(PYTHON) -m venv $(VENV)
	$(PIP) install --upgrade pip
	$(PIP) install -r requirements.txt

venv: $(VENV)/bin/activate

lint: venv
	$(VENV_ACTIVATE) && ansible-lint $(PLAYBOOK)

check: venv
	$(VENV_ACTIVATE) && ansible-playbook -i $(INVENTORY) $(PLAYBOOK) --syntax-check

ping: venv
	$(VENV_ACTIVATE) && ansible nexus -i $(INVENTORY) -m ansible.builtin.ping

deploy: venv
	$(VENV_ACTIVATE) && ansible-playbook -i $(INVENTORY) $(PLAYBOOK)

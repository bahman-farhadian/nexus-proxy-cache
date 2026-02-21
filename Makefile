.DEFAULT_GOAL := help
.PHONY: help venv lint check ping deploy

INVENTORY ?= inventories/host.yml
PLAYBOOK ?= site.yml
VENV ?= .venv
PYTHON ?= python3
PIP := $(VENV)/bin/pip
VENV_ACTIVATE := . $(VENV)/bin/activate

help:
	@echo "Available targets:"
	@echo "  make venv    - create .venv and install Python dependencies"
	@echo "  make lint    - run ansible-lint on $(PLAYBOOK)"
	@echo "  make check   - run ansible-playbook syntax check"
	@echo "  make ping    - test SSH/Ansible connectivity to nexus group"
	@echo "  make deploy  - apply $(PLAYBOOK) to $(INVENTORY)"

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

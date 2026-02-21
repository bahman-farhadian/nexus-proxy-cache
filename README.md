# nexus-proxy-cache

Ansible project to provision a Debian 13 VM and deploy **Sonatype Nexus Repository OSS (Nexus 3)** as a private caching proxy for:

- Debian APT repositories
- Docker Hub image pulls

This project uses a **native Nexus installation managed by systemd** (no Docker, no docker-compose) and plain HTTP on a private network.

## Repository Layout

- `site.yml`
- `inventories/dev/hosts.ini`
- `inventories/prod/hosts.ini`
- `group_vars/all.yml`
- `group_vars/all/vault.yml`
- `roles/vm_baseline/`
- `roles/java/`
- `roles/nexus_install/`
- `roles/nexus_systemd/`
- `roles/nexus_config/`
- `docs/decisions.md`
- `docs/client-setup.md`
- `docs/runbook.md`
- `requirements.txt`
- `.gitignore`
- `Makefile`

## Prerequisites

- Python 3 with `venv` support on your laptop
- SSH access to Debian 13 VM
- VM user with sudo privileges
- Outbound internet access from VM to:
  - `download.sonatype.com`
  - Debian mirrors
  - Docker Hub (`registry-1.docker.io`)
- Hostname resolution for `nexus_hostname` (default `repo.idops.local`) from:
  - the Nexus VM itself
  - client VMs that will use the cache

## Quick Start (End-to-End)

1. Create local tooling virtualenv:

```bash
make venv
source .venv/bin/activate
```

2. Update inventory target:

```bash
vi inventories/dev/hosts.ini
```

Set your VM host/IP and SSH user.

3. Confirm/edit core vars (especially hostname/port if needed):

```bash
vi group_vars/all.yml
```

Important vars:
- `nexus_hostname`
- `nexus_http_port`
- `nexus_version`

4. Make sure `nexus_hostname` resolves on the Nexus VM and on client VMs.

If you are not using DNS, add hosts entries:

```bash
echo "<NEXUS_VM_PRIVATE_IP> repo.idops.local" | sudo tee -a /etc/hosts
```

5. Set vault secret placeholder and encrypt:

```bash
vi group_vars/all/vault.yml
ansible-vault encrypt group_vars/all/vault.yml
```

6. Validate and deploy:

```bash
make lint
make check
make deploy
```

Equivalent explicit commands:

```bash
ansible-playbook -i inventories/dev/hosts.ini site.yml --syntax-check
ansible-playbook -i inventories/dev/hosts.ini site.yml --ask-vault-pass
```

Use a different inventory (example: prod):

```bash
make check INVENTORY=inventories/prod/hosts.ini
make deploy INVENTORY=inventories/prod/hosts.ini
```

## Ansible Vault Quick Help

Use Vault to keep `vault_nexus_admin_password` encrypted in `group_vars/all/vault.yml`.

Create/update the secret and encrypt:

```bash
vi group_vars/all/vault.yml
ansible-vault encrypt group_vars/all/vault.yml
```

Edit the encrypted file later (recommended):

```bash
ansible-vault edit group_vars/all/vault.yml
```

View encrypted content temporarily:

```bash
ansible-vault view group_vars/all/vault.yml
```

Decrypt back to plaintext (only if needed):

```bash
ansible-vault decrypt group_vars/all/vault.yml
```

Run playbook and provide vault password interactively:

```bash
ansible-playbook -i inventories/dev/hosts.ini site.yml --ask-vault-pass
```

Optional non-interactive method (CI/local automation):

```bash
ansible-playbook -i inventories/dev/hosts.ini site.yml --vault-password-file .vault_pass.txt
```

Do not commit `.vault_pass.txt` (or any vault password file) to git.
When finished, leave the virtualenv with `deactivate`.

## What This Deploys

- Baseline VM packages + restrictive `nftables` firewall (22 + Nexus HTTP port)
- Java runtime (`openjdk-17-jre-headless` by default)
- Native Nexus OSS under `/opt/nexus/current`
- Nexus data directory under `/var/lib/nexus`
- `systemd` service: `nexus.service`
- Nexus bootstrap via REST API:
  - admin password set from vault
  - APT proxy repositories (+ optional APT group)
  - Docker Hub proxy repository (+ optional Docker group)

## Post-Deploy Verification

On the Nexus VM:

```bash
sudo systemctl status nexus --no-pager
curl -sf http://repo.idops.local:8081/service/rest/v1/status | jq
```

If you changed hostname or port, replace `repo.idops.local:8081` accordingly.

## VM Migration Guide: Replace Official Repositories With Nexus

Use this on client VMs after Nexus deployment.

### Debian APT clients

If APT group exists:

```bash
sudo tee /etc/apt/sources.list.d/nexus.list >/dev/null <<'EOL'
deb http://<NEXUS_HOSTNAME>:8081/repository/debian-apt-group trixie main contrib non-free-firmware
deb http://<NEXUS_HOSTNAME>:8081/repository/debian-apt-group trixie-security main contrib non-free-firmware
EOL
```

If APT group is not available, use per-upstream proxies:

```bash
sudo tee /etc/apt/sources.list.d/nexus.list >/dev/null <<'EOL'
deb http://<NEXUS_HOSTNAME>:8081/repository/debian-main-proxy trixie main contrib non-free-firmware
deb http://<NEXUS_HOSTNAME>:8081/repository/debian-security-proxy trixie-security main contrib non-free-firmware
EOL
```

Disable old source files and refresh:

```bash
sudo rm -f /etc/apt/sources.list
sudo rm -f /etc/apt/sources.list.d/debian.sources
sudo apt-get update
```

### Docker clients

Configure `/etc/docker/daemon.json`:

```json
{
  "insecure-registries": ["<NEXUS_HOSTNAME>:8081"],
  "registry-mirrors": ["http://<NEXUS_HOSTNAME>:8081/repository/docker-group"]
}
```

If `enable_docker_group` is `false`, use:

```json
"registry-mirrors": ["http://<NEXUS_HOSTNAME>:8081/repository/docker-hub-proxy"]
```

Apply and test:

```bash
sudo systemctl restart docker
docker pull alpine:latest
docker pull nginx:latest
```

## Additional Docs

- Detailed client instructions: `docs/client-setup.md`
- Operational runbook: `docs/runbook.md`
- Design decisions: `docs/decisions.md`

## Notes

- TLS/SSL is intentionally not configured (private-network deployment).
- Keep Nexus restricted to private network paths.
- APT group endpoint support can vary by Nexus build; this project handles unsupported APT group endpoint by default.

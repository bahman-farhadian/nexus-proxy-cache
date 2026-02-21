# nexus-proxy-cache

Ansible project to provision a Debian 13 VM and deploy **Sonatype Nexus Repository OSS (Nexus 3)** as a private caching proxy for:

- Debian APT repositories
- Docker Hub image pulls

This project uses a **native Nexus installation managed by systemd** (no Docker, no docker-compose) and plain HTTP on a private network.

## What Nexus Does Here (Beginner Summary)

- Your VMs pull APT packages and Docker images from Nexus, not directly from upstream internet repositories.
- On first request, Nexus downloads from upstream and stores content locally.
- On next requests, Nexus serves from local cache, reducing external bandwidth and speeding up repeated pulls.
- This project creates:
  - APT proxy repos: `debian-main-proxy`, `debian-security-proxy`
  - Optional APT group repo: `debian-apt-group`
  - Docker proxy repo: `docker-hub-proxy`
  - Optional Docker group repo: `docker-group`

## Repository Layout

- `site.yml`
- `inventories/host.yml`
- `group_vars/all.yml`
- `group_vars/all/vault.yml`
- `roles/vm_baseline/`
- `roles/java/`
- `roles/nexus_install/`
- `roles/nexus_systemd/`
- `roles/nexus_nginx/`
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
nano inventories/host.yml
```

Set your VM connection details:
- `ansible_host`: Nexus VM IP or hostname
- `ansible_user`: SSH user
- `ansible_port`: SSH port (`22` unless you changed it)
- `ansible_python_interpreter`: usually `/usr/bin/python3`

3. Confirm/edit core vars (especially hostname/port if needed):

```bash
nano group_vars/all.yml
```

Important vars:
- `nexus_hostname`
- `nexus_public_port`
- `nexus_http_port` (internal Nexus app port, usually keep `8081`)
- `nexus_version`
- `enable_apt_group`
- `enable_docker_group`

4. Make sure `nexus_hostname` resolves on the Nexus VM and on client VMs.

If you are not using DNS, add hosts entries:

```bash
echo "<NEXUS_VM_PRIVATE_IP> repo.idops.local" | sudo tee -a /etc/hosts
```

5. Set vault secret placeholder and encrypt:

```bash
nano group_vars/all/vault.yml
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
ansible-playbook -i inventories/host.yml site.yml --syntax-check
ansible-playbook -i inventories/host.yml site.yml --ask-vault-pass
```

## Ansible Vault Quick Help

Use Vault to keep `vault_nexus_admin_password` encrypted in `group_vars/all/vault.yml`.

Create/update the secret and encrypt:

```bash
nano group_vars/all/vault.yml
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
ansible-playbook -i inventories/host.yml site.yml --ask-vault-pass
```

Optional non-interactive method (CI/local automation):

```bash
ansible-playbook -i inventories/host.yml site.yml --vault-password-file .vault_pass.txt
```

Do not commit `.vault_pass.txt` (or any vault password file) to git.
When finished, leave the virtualenv with `deactivate`.

## What This Deploys

- Baseline VM packages + restrictive `nftables` firewall (SSH port from `ansible_port` + Nexus public HTTP port)
- Optional iptables compatibility rule: if `/etc/iptables/rules.v4` exists, ensure ACCEPT for Nexus public port
- Java runtime (`openjdk-17-jre-headless` by default)
- Native Nexus OSS under `/opt/nexus/current` (bound to loopback on internal port)
- Nexus data directory under `/var/lib/nexus`
- `systemd` service: `nexus.service`
- Nginx reverse proxy on `nexus_public_port` with `server_name nexus_hostname`
- Nexus bootstrap via REST API:
  - admin password set from vault
  - APT proxy repositories (+ optional APT group)
  - Docker Hub proxy repository (+ optional Docker group)

## First Nexus Login (After Deploy)

1. Open Nexus UI:
```text
http://<nexus_hostname>
```
If `nexus_public_port` is not `80`, use `http://<nexus_hostname>:<nexus_public_port>`.
2. Login username: `admin`
3. Login password: value of `vault_nexus_admin_password` from your encrypted `group_vars/all/vault.yml`.
4. In Nexus UI, check repository names under **Repositories**:
   - `debian-main-proxy`
   - `debian-security-proxy`
   - `debian-apt-group` (if enabled/supported)
   - `docker-hub-proxy`
   - `docker-group` (if enabled)

## Post-Deploy Verification

On the Nexus VM:

```bash
sudo systemctl status nexus --no-pager
sudo systemctl status nginx --no-pager
curl -sf http://repo.idops.local/service/rest/v1/status | jq
```

If you changed hostname or public port, replace URL accordingly.

## VM Migration Guide: Replace Official Repositories With Nexus

Use this on client VMs after Nexus deployment.

### Debian APT clients

If APT group exists:

```bash
sudo tee /etc/apt/sources.list.d/nexus.list >/dev/null <<'EOL'
deb http://<NEXUS_HOSTNAME>/repository/debian-apt-group trixie main contrib non-free-firmware
deb http://<NEXUS_HOSTNAME>/repository/debian-apt-group trixie-security main contrib non-free-firmware
EOL
```

If APT group is not available, use per-upstream proxies:

```bash
sudo tee /etc/apt/sources.list.d/nexus.list >/dev/null <<'EOL'
deb http://<NEXUS_HOSTNAME>/repository/debian-main-proxy trixie main contrib non-free-firmware
deb http://<NEXUS_HOSTNAME>/repository/debian-security-proxy trixie-security main contrib non-free-firmware
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
  "insecure-registries": ["<NEXUS_HOSTNAME>"],
  "registry-mirrors": ["http://<NEXUS_HOSTNAME>/repository/docker-group"]
}
```

If `enable_docker_group` is `false`, use:

```json
"registry-mirrors": ["http://<NEXUS_HOSTNAME>/repository/docker-hub-proxy"]
```

Apply and test:

```bash
sudo systemctl restart docker
docker pull alpine:latest
docker pull nginx:latest
```

If Docker pull fails with mirror issues, test direct proxy endpoint by disabling group and using:
`http://<NEXUS_HOSTNAME>/repository/docker-hub-proxy`.

## Additional Docs

- Detailed client instructions: `docs/client-setup.md`
- Operational runbook: `docs/runbook.md`
- Design decisions: `docs/decisions.md`

## Notes

- TLS/SSL is intentionally not configured (private-network deployment).
- Keep Nexus restricted to private network paths.
- APT group endpoint support can vary by Nexus build; this project handles unsupported APT group endpoint by default.

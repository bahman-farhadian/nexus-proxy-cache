# nexus-proxy-cache

Ansible project to provision a Debian 13 VM and deploy **Sonatype Nexus Repository OSS (Nexus 3)** as a private caching proxy for:

- Debian 12 and Debian 13 APT repositories
- Docker Hub image pulls

This project uses a **native Nexus installation managed by systemd** (no Docker, no docker-compose).
Default mode is plain HTTP for private networks; optional public TLS mode with Let's Encrypt is supported.

## What Nexus Does Here (Beginner Summary)

- Your VMs pull APT packages and Docker images from Nexus, not directly from upstream internet repositories.
- On first request, Nexus downloads from upstream and stores content locally.
- On next requests, Nexus serves from local cache, reducing external bandwidth and speeding up repeated pulls.
- This project creates:
  - APT proxy repos:
    - `debian12-main-proxy`, `debian12-security-proxy`
    - `debian13-main-proxy`, `debian13-security-proxy`
  - Optional APT group repo: `debian-apt-group`
  - Docker proxy repo: `docker-hub-proxy`
  - Optional Docker group repo: `docker-group`

## Repository Layout

- `site.yml`
- `inventories/host.yml`
- `group_vars/all.yml`
- `roles/vm_baseline/`
- `roles/java/`
- `roles/postgresql/`
- `roles/nexus_install/`
- `roles/nexus_systemd/`
- `roles/nexus_nginx/`
- `roles/nexus_config/`
- `docs/decisions.md`
- `docs/client-setup.md`
- `docs/runbook.md`
- `requirements.txt`
- `.nexus_admin_password.example`
- `.nexus_db_password.example`
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
  - client VMs that will use the cache
  - operator machines that access the Nexus UI/API by hostname
- For public TLS mode:
  - DNS record for `nexus_tls_domain` must point to `nexus_public_ip`
  - inbound TCP `80` and `443` must be reachable from the internet
  - Let's Encrypt does not issue certificates for raw IP addresses

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
- `nexus_public_ip`
- `nexus_public_port` (keep `80` when TLS mode is enabled)
- `nexus_http_port` (internal Nexus app port, usually keep `8081`)
- `nexus_tls_enabled` (`false` for private HTTP-only, `true` for public TLS)
- `nexus_tls_domain` (must be a DNS name, not an IP)
- `nexus_tls_email` (used by Let's Encrypt)
- `nexus_https_port`
- `nexus_version`
- `nexus_database_backend` (`postgresql` or `h2`; default `postgresql`)
- `enable_apt_group`
- `enable_docker_group`

`postgresql` is the default backend to avoid Nexus H2 recommended-limit warnings on the status page.

4. Make sure `nexus_hostname` resolves on client VMs and your operator machine.

If you are not using DNS, add hosts entries:

```bash
echo "<NEXUS_VM_PRIVATE_IP> repo.idops.local" | sudo tee -a /etc/hosts
```

5. Create local Nexus admin password file (ignored by git):

```bash
cp .nexus_admin_password.example .nexus_admin_password
nano .nexus_admin_password
chmod 600 .nexus_admin_password
```

The loader uses the first non-empty, non-comment line as the password.

6. Create local Nexus PostgreSQL password file (ignored by git):

```bash
cp .nexus_db_password.example .nexus_db_password
nano .nexus_db_password
chmod 600 .nexus_db_password
```

This password is used for the PostgreSQL role/user that backs Nexus datastore.

7. Validate and deploy:

```bash
make lint
make check
make ping
make deploy
```

Useful command help:

```bash
make help
```

`make help` lists:
- `make venv`
- `make lint`
- `make check`
- `make ping`
- `make deploy`

Equivalent explicit commands:

```bash
ansible-playbook -i inventories/host.yml site.yml --syntax-check
ansible nexus -i inventories/host.yml -m ansible.builtin.ping
ansible-playbook -i inventories/host.yml site.yml
```

## Admin Password File Notes

- Vault is deprecated in this project.
- Admin password is read from `.nexus_admin_password`.
- PostgreSQL password is read from `.nexus_db_password`.
- The password file is gitignored and must stay local on your control host.
- The DB password file is gitignored and must stay local on your control host.
- If you already changed the Nexus admin password manually, set your password file to that exact value before rerunning playbooks.
- The role also tries fallback `admin123` only when desired password fails.
- Nexus secret-key seed files (`.nexus_secret_key`, `.nexus_secret_salt`, `.nexus_secret_iv`) are generated locally and gitignored.

## HTTP vs TLS

- Private/local network deployment: HTTP-only is acceptable (`nexus_tls_enabled: false`).
- Public internet deployment: enable TLS (`nexus_tls_enabled: true`) and configure:
  - `nexus_public_ip`: public VM IP
  - `nexus_tls_domain`: public DNS name pointing to that IP
  - `nexus_tls_email`: registration email for Let's Encrypt
- Certificate issuance and renewal:
  - certs are issued with `certbot` (HTTP-01 webroot flow)
  - auto-renew is managed by `certbot.timer` (enabled by Ansible)
  - Let's Encrypt validates a DNS name, not a raw public IP

### Public TLS quick vars

Set these in `group_vars/all.yml` for internet-facing mode:

```yaml
nexus_tls_enabled: true
nexus_public_ip: 203.0.113.10
nexus_tls_domain: repo.example.com
nexus_tls_email: ops@example.com
nexus_https_port: 443
```

## What This Deploys

- Baseline VM packages + restrictive `nftables` firewall (SSH port from `ansible_port` + Nexus public HTTP port)
- Optional iptables compatibility mode: if `/etc/iptables/rules.v4` exists, manage an Ansible block
  before `-A INPUT -j DROP` for SSH + Nexus ports and restart `netfilter-persistent` when available
- Java runtime (`openjdk-21-jre-headless` by default)
- PostgreSQL datastore (local service by default) to avoid H2 scaling-limit warnings
- Native Nexus OSS under `/opt/nexus/current` (bound to loopback on internal port)
- Nexus data directory under `/var/lib/nexus`
- `systemd` service: `nexus.service`
- Nginx reverse proxy on `nexus_public_port` (HTTP) with `server_name nexus_hostname`
- Optional TLS termination on `nexus_https_port` with Let's Encrypt (`certbot.timer` auto-renew)
- Nexus bootstrap via REST API:
  - admin password set to value in `.nexus_admin_password`
  - APT proxy repositories (+ optional APT group)
  - Docker Hub proxy repository (+ optional Docker group)
- Default Nexus package version pinned in this repo: `3.89.1-02`
- Nexus custom secrets key file is managed automatically to avoid the "Default Secret Encryption Key" warning

## First Nexus Login (After Deploy)

1. Open Nexus UI:
```text
<http|https>://<nexus_hostname>
```
If TLS is enabled, use `https` and `nexus_https_port` (when not `443`).
If TLS is disabled, use `http` and `nexus_public_port` (when not `80`).
2. Login username: `admin`
3. Login password: value from `.nexus_admin_password`
4. In Nexus UI, check repository names under **Repositories**:
   - `debian12-main-proxy`
   - `debian12-security-proxy`
   - `debian13-main-proxy`
   - `debian13-security-proxy`
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

If TLS is enabled, switch URL to `https://...` and use `nexus_https_port` when not `443`.
In TLS mode also check renewal timer: `sudo systemctl status certbot.timer --no-pager`.

## VM Migration Guide: Replace Official Repositories With Nexus

Use this on client VMs after Nexus deployment.
Use `<NEXUS_SCHEME>` as `http` in private mode or `https` in TLS mode.

### Debian APT clients

If APT group exists, use entries for your distro:
Use only the lines matching your Debian release (`bookworm` for Debian 12, `trixie` for Debian 13).

```bash
sudo tee /etc/apt/sources.list.d/nexus.list >/dev/null <<'EOL'
deb <NEXUS_SCHEME>://<NEXUS_HOSTNAME>/repository/debian-apt-group bookworm main contrib non-free-firmware
deb <NEXUS_SCHEME>://<NEXUS_HOSTNAME>/repository/debian-apt-group bookworm-security main contrib non-free-firmware
deb <NEXUS_SCHEME>://<NEXUS_HOSTNAME>/repository/debian-apt-group trixie main contrib non-free-firmware
deb <NEXUS_SCHEME>://<NEXUS_HOSTNAME>/repository/debian-apt-group trixie-security main contrib non-free-firmware
EOL
```

If APT group is not available, use per-upstream proxies:
Use only the lines matching your Debian release (`bookworm` for Debian 12, `trixie` for Debian 13).

```bash
sudo tee /etc/apt/sources.list.d/nexus.list >/dev/null <<'EOL'
deb <NEXUS_SCHEME>://<NEXUS_HOSTNAME>/repository/debian12-main-proxy bookworm main contrib non-free-firmware
deb <NEXUS_SCHEME>://<NEXUS_HOSTNAME>/repository/debian12-security-proxy bookworm-security main contrib non-free-firmware
deb <NEXUS_SCHEME>://<NEXUS_HOSTNAME>/repository/debian13-main-proxy trixie main contrib non-free-firmware
deb <NEXUS_SCHEME>://<NEXUS_HOSTNAME>/repository/debian13-security-proxy trixie-security main contrib non-free-firmware
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
  "registry-mirrors": ["<NEXUS_SCHEME>://<NEXUS_HOSTNAME>/repository/docker-group"]
}
```

If `enable_docker_group` is `false`, use:

```json
"registry-mirrors": ["<NEXUS_SCHEME>://<NEXUS_HOSTNAME>/repository/docker-hub-proxy"]
```

If TLS mode is enabled with a valid public certificate, remove `insecure-registries`.

Apply and test:

```bash
sudo systemctl restart docker
docker pull alpine:latest
docker pull nginx:latest
```

If Docker pull fails with mirror issues, test direct proxy endpoint by disabling group and using:
`<NEXUS_SCHEME>://<NEXUS_HOSTNAME>/repository/docker-hub-proxy`.

## Additional Docs

- Detailed client instructions: `docs/client-setup.md`
- Operational runbook: `docs/runbook.md`
- Design decisions: `docs/decisions.md`

## Notes

- Private-network mode can stay HTTP-only; public mode should enable TLS.
- Keep Nexus restricted to private network paths.
- APT group endpoint support can vary by Nexus build; this project handles unsupported APT group endpoint by default.
- When `nexus_database_backend: postgresql`, the playbook validates Nexus status checks and warns if Nexus still reports H2 after an automatic restart attempt.
- The playbook also manages a custom `nexus-secrets.json` key and waits for the default-key warning to clear.

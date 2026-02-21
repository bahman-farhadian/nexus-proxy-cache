# nexus-proxy-cache

Ansible project to provision a Debian 13 VM and deploy **Sonatype Nexus Repository OSS (Nexus 3)** as a private caching proxy for:

- Debian APT upstreams
- Docker Hub pulls

This project uses a **native Nexus installation managed by systemd** (no Docker, no docker-compose) and keeps Nexus on plain HTTP for private-network use behind NAT.

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
- `Makefile`

## Prerequisites

- Ansible installed on your laptop
- SSH access to Debian 13 VM
- VM user with sudo privileges
- Outbound internet access from VM to:
  - `download.sonatype.com`
  - Debian mirrors
  - Docker Hub (`registry-1.docker.io`)
- Hostname resolution for `nexus_hostname` (default `repo.idops.local`) from clients and from the Nexus VM itself.

## Vault Secret Setup

1. Edit vault placeholder:

```bash
vi group_vars/all/vault.yml
```

2. Set a strong value for `vault_nexus_admin_password`.

3. Encrypt the file:

```bash
ansible-vault encrypt group_vars/all/vault.yml
```

## How To Run

```bash
make lint
```

```bash
ansible-playbook -i inventories/dev/hosts.ini site.yml --syntax-check
```

```bash
ansible-playbook -i inventories/dev/hosts.ini site.yml --ask-vault-pass
```

You can also use:

```bash
make check
make deploy
```

## VM Migration Guide: Use Nexus Instead of Official Repositories

Use this after deployment so clients pull through Nexus cache.
Default hostname from this project: `repo.idops.local`.
If needed, add a hosts entry on clients (and on Nexus VM for Ansible API tasks):

```bash
echo "<NEXUS_VM_PRIVATE_IP> repo.idops.local" | sudo tee -a /etc/hosts
```

### 1) Point Debian APT to Nexus

On each Debian client VM, replace official Debian sources with Nexus sources.

If APT group creation is available in your Nexus build:

```bash
sudo tee /etc/apt/sources.list.d/nexus.list >/dev/null <<'EOL'
deb http://<NEXUS_HOSTNAME>:8081/repository/debian-apt-group trixie main contrib non-free-firmware
deb http://<NEXUS_HOSTNAME>:8081/repository/debian-apt-group trixie-security main contrib non-free-firmware
EOL
```

If APT group is not available, use the individual proxies:

```bash
sudo tee /etc/apt/sources.list.d/nexus.list >/dev/null <<'EOL'
deb http://<NEXUS_HOSTNAME>:8081/repository/debian-main-proxy trixie main contrib non-free-firmware
deb http://<NEXUS_HOSTNAME>:8081/repository/debian-security-proxy trixie-security main contrib non-free-firmware
EOL
```

Disable old Debian source files (paths may differ by image):

```bash
sudo rm -f /etc/apt/sources.list
sudo rm -f /etc/apt/sources.list.d/debian.sources
```

Then refresh:

```bash
sudo apt-get update
```

### 2) Point Docker to Nexus (Docker Hub cache)

Create or update `/etc/docker/daemon.json` on each Docker client VM:

```json
{
  "insecure-registries": ["<NEXUS_HOSTNAME>:8081"],
  "registry-mirrors": ["http://<NEXUS_HOSTNAME>:8081/repository/docker-group"]
}
```

If `enable_docker_group` is `false`, use `docker-hub-proxy` instead of `docker-group`.

Restart Docker:

```bash
sudo systemctl restart docker
```

Test pulls:

```bash
docker pull alpine:latest
docker pull nginx:latest
```

## Notes

- No TLS is configured by design for this private deployment.
- Keep Nexus reachable only on private network segments.
- APT group support may differ by Nexus build; this project handles unsupported APT group endpoint gracefully by default.

# Client Setup

This guide shows how Debian and Docker clients should consume Nexus cache instead of official upstreams.

## Variables Used In Examples
- `<NEXUS_HOSTNAME>`: Nexus hostname (default `repo.idops.local`)
- Nexus public HTTP port: `80` (default, served by Nginx reverse proxy)
- If you change `nexus_public_port` from `80`, append `:<PORT>` to all example URLs below.

Ensure clients resolve `<NEXUS_HOSTNAME>`. If DNS is not available:

```bash
echo "<NEXUS_VM_PRIVATE_IP> repo.idops.local" | sudo tee -a /etc/hosts
```

## Repository Endpoints Created By This Project

- APT proxy: `/repository/debian-main-proxy`
- APT security proxy: `/repository/debian-security-proxy`
- APT group (if enabled/supported): `/repository/debian-apt-group`
- Docker proxy: `/repository/docker-hub-proxy`
- Docker group (if enabled): `/repository/docker-group`

## Debian APT clients

### Option A: APT group repository (preferred when available)

```bash
sudo tee /etc/apt/sources.list.d/nexus.list >/dev/null <<'EOL'
deb http://<NEXUS_HOSTNAME>/repository/debian-apt-group trixie main contrib non-free-firmware
deb http://<NEXUS_HOSTNAME>/repository/debian-apt-group trixie-security main contrib non-free-firmware
EOL
```

### Option B: Per-upstream APT proxies (fallback)

```bash
sudo tee /etc/apt/sources.list.d/nexus.list >/dev/null <<'EOL'
deb http://<NEXUS_HOSTNAME>/repository/debian-main-proxy trixie main contrib non-free-firmware
deb http://<NEXUS_HOSTNAME>/repository/debian-security-proxy trixie-security main contrib non-free-firmware
EOL
```

Disable existing official sources and refresh metadata:

```bash
sudo rm -f /etc/apt/sources.list
sudo rm -f /etc/apt/sources.list.d/debian.sources
sudo apt-get update
```

If Option A returns 404/400 in your environment, use Option B.

## Docker clients

Configure `/etc/docker/daemon.json`:

```json
{
  "insecure-registries": ["<NEXUS_HOSTNAME>"],
  "registry-mirrors": ["http://<NEXUS_HOSTNAME>/repository/docker-group"]
}
```

If `enable_docker_group` is disabled, use:

```json
"registry-mirrors": ["http://<NEXUS_HOSTNAME>/repository/docker-hub-proxy"]
```

Apply and validate:

```bash
sudo systemctl restart docker
docker pull busybox:latest
docker pull ubuntu:latest
```

If `docker-group` is not enabled, point mirror to:
`http://<NEXUS_HOSTNAME>/repository/docker-hub-proxy`.

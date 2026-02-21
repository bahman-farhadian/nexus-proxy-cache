# Client Setup

This guide shows how Debian and Docker clients should consume Nexus cache instead of official upstreams.
Default repository set supports Debian 12 (`bookworm`) and Debian 13 (`trixie`).

## Variables Used In Examples
- `<NEXUS_HOSTNAME>`: Nexus hostname (default `repo.idops.local`)
- `<NEXUS_SCHEME>`: `http` (default private mode) or `https` (TLS mode)
- If HTTP mode is used and `nexus_public_port` is not `80`, append `:<PORT>`.
- If TLS mode is used and `nexus_https_port` is not `443`, append `:<PORT>`.

Ensure clients resolve `<NEXUS_HOSTNAME>`. If DNS is not available:

```bash
echo "<NEXUS_VM_PRIVATE_IP> repo.idops.local" | sudo tee -a /etc/hosts
```

## Repository Endpoints Created By This Project

- APT proxy (Debian 12): `/repository/debian12-main-proxy`
- APT security proxy (Debian 12): `/repository/debian12-security-proxy`
- APT proxy (Debian 13): `/repository/debian13-main-proxy`
- APT security proxy (Debian 13): `/repository/debian13-security-proxy`
- APT group (if enabled/supported): `/repository/debian-apt-group`
- Docker proxy: `/repository/docker-hub-proxy`
- Docker group (if enabled): `/repository/docker-group`

## Debian APT clients

### Option A: APT group repository (preferred when available)

Use only the lines matching your Debian release (`bookworm` for Debian 12, `trixie` for Debian 13).

```bash
sudo tee /etc/apt/sources.list.d/nexus.list >/dev/null <<'EOL'
deb <NEXUS_SCHEME>://<NEXUS_HOSTNAME>/repository/debian-apt-group bookworm main contrib non-free-firmware
deb <NEXUS_SCHEME>://<NEXUS_HOSTNAME>/repository/debian-apt-group bookworm-security main contrib non-free-firmware
deb <NEXUS_SCHEME>://<NEXUS_HOSTNAME>/repository/debian-apt-group trixie main contrib non-free-firmware
deb <NEXUS_SCHEME>://<NEXUS_HOSTNAME>/repository/debian-apt-group trixie-security main contrib non-free-firmware
EOL
```

### Option B: Per-upstream APT proxies (fallback)

Use only the lines matching your Debian release (`bookworm` for Debian 12, `trixie` for Debian 13).

```bash
sudo tee /etc/apt/sources.list.d/nexus.list >/dev/null <<'EOL'
deb <NEXUS_SCHEME>://<NEXUS_HOSTNAME>/repository/debian12-main-proxy bookworm main contrib non-free-firmware
deb <NEXUS_SCHEME>://<NEXUS_HOSTNAME>/repository/debian12-security-proxy bookworm-security main contrib non-free-firmware
deb <NEXUS_SCHEME>://<NEXUS_HOSTNAME>/repository/debian13-main-proxy trixie main contrib non-free-firmware
deb <NEXUS_SCHEME>://<NEXUS_HOSTNAME>/repository/debian13-security-proxy trixie-security main contrib non-free-firmware
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
  "registry-mirrors": ["<NEXUS_SCHEME>://<NEXUS_HOSTNAME>/repository/docker-group"]
}
```

If TLS mode is enabled with a valid public certificate, remove `insecure-registries`.

If `enable_docker_group` is disabled, use:

```json
"registry-mirrors": ["<NEXUS_SCHEME>://<NEXUS_HOSTNAME>/repository/docker-hub-proxy"]
```

Apply and validate:

```bash
sudo systemctl restart docker
docker pull busybox:latest
docker pull ubuntu:latest
```

If `docker-group` is not enabled, point mirror to:
`<NEXUS_SCHEME>://<NEXUS_HOSTNAME>/repository/docker-hub-proxy`.

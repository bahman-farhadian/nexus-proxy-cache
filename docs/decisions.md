# Architecture Decisions

## 1. Native Nexus installation
- Decision: Install Nexus OSS from Sonatype tarball under `/opt/nexus` and run via systemd.
- Why: Meets requirement to avoid containerized deployment and keeps lifecycle under OS service management.

## 2. Firewall strategy
- Decision: Use `nftables` with a restrictive default policy.
- Why: Native Debian firewall, idempotent through a managed template.
- Policy: Allow inbound TCP `ansible_port` (fallback `22`) and `nexus_public_port` only (plus optional `vm_baseline_extra_tcp_ports`).
- Compatibility: If `/etc/iptables/rules.v4` exists, ensure an ACCEPT rule is present for `nexus_public_port`.

## 3. Java runtime source
- Decision: Install Java runtime from Debian packages (`openjdk-17-jre-headless` by default).
- Why: Keeps JRE maintenance in OS package management.

## 4. Nexus configuration via REST API
- Decision: Use `ansible.builtin.uri` for bootstrapping admin password and repository creation.
- Why: Avoids brittle shell/CLI parsing and keeps idempotency explicit.

## 5. Repository model
- Decision: Create APT proxies for Debian and security upstreams; optionally create APT group if endpoint exists.
- Why: Some Nexus builds expose APT proxy endpoints but not APT group; implementation remains usable without manual edits.

## 6. Docker proxy access mode
- Decision: Enable path-based Docker routing and keep all client traffic on Nexus public HTTP endpoint (Nginx on `80` by default).
- Why: Aligns with private HTTP-only deployment and avoids opening additional connector ports by default.

## 7. Public HTTP via Nginx
- Decision: Keep Nexus on internal port `8081` and publish HTTP on port `80` through Nginx.
- Why: Nexus runs as non-root service while clients still get a standard HTTP endpoint (`http://repo.idops.local`).

## 8. Secrets handling
- Decision: Keep admin password in `group_vars/all/vault.yml` only.
- Why: No plaintext secrets in repo and compatible with standard Ansible Vault workflows.

## 9. Stable Nexus hostname
- Decision: Use `nexus_hostname` (default `repo.idops.local`) as the canonical endpoint for Nexus URLs.
- Why: Avoids hard-coded private IPs in client configuration and allows IP changes without updating clients.

## 10. Python tooling isolation
- Decision: Use project-local `.venv` with `requirements.txt` via `make venv`.
- Why: Keeps Ansible and lint versions isolated from host OS packages and avoids global dependency drift.

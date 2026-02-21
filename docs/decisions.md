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
- Decision: Install Java runtime from Debian packages (`openjdk-21-jre-headless` by default).
- Why: Keeps JRE maintenance in OS package management.

## 4. Nexus configuration via REST API
- Decision: Use `ansible.builtin.uri` for bootstrapping admin password and repository creation.
- Why: Avoids brittle shell/CLI parsing and keeps idempotency explicit.

## 5. Repository model
- Decision: Create APT proxies for Debian 12 (`bookworm`) and Debian 13 (`trixie`) plus their security upstreams; optionally create APT group if endpoint exists.
- Why: Teams often run mixed Debian versions, and some Nexus builds expose APT proxy endpoints but not APT group; implementation remains usable without manual edits.

## 6. Docker proxy access mode
- Decision: Enable path-based Docker routing and keep all client traffic on Nexus public HTTP endpoint (Nginx on `80` by default).
- Why: Aligns with private HTTP-only deployment and avoids opening additional connector ports by default.

## 7. Public endpoint via Nginx
- Decision: Keep Nexus on internal port `8081` and publish through Nginx; default is HTTP on port `80` for private networks.
- Why: Nexus runs as non-root service while clients get a stable endpoint.
- Extension: Optional TLS mode uses Let's Encrypt (`certbot`) with automatic renewal via `certbot.timer`.
- Constraint: Let's Encrypt requires DNS hostname validation and does not issue certs for raw IP addresses.

## 8. Secrets handling
- Decision: Deprecate Ansible Vault for this project and load the Nexus admin password from local file `.nexus_admin_password` on the control host.
- Why: Reduces onboarding friction and keeps the workflow straightforward for operators.

## 9. Stable Nexus hostname
- Decision: Use `nexus_hostname` (default `repo.idops.local`) as the canonical endpoint for Nexus URLs.
- Why: Avoids hard-coded private IPs in client configuration and allows IP changes without updating clients.
- Note: Ansible bootstrap calls use `nexus_rest_api_config_base_url` on loopback to avoid DNS dependency during provisioning.

## 10. Python tooling isolation
- Decision: Use project-local `.venv` with `requirements.txt` via `make venv`.
- Why: Keeps Ansible and lint versions isolated from host OS packages and avoids global dependency drift.

## 11. Nexus version tracking
- Decision: Track latest stable GA Nexus OSS release from Sonatype official release status/download pages.
- Why: Sonatype publishes GA/maintenance status but no LTSC channel; pinning the latest GA keeps security and compatibility current.

## 12. Nexus secret encryption key management
- Decision: Manage `nexus-secrets.json` with a custom key and fixed encryption values from Ansible.
- Why: Avoids the "Default Secret Encryption Key" warning and enables predictable re-encryption workflows.

## 13. Datastore backend
- Decision: Default Nexus datastore backend to PostgreSQL (`nexus_database_backend: postgresql`).
- Why: Removes H2 recommended-limit warnings from Nexus status checks and provides better production scalability.
- Implementation: Local PostgreSQL service is provisioned by default; remote PostgreSQL is supported by setting `nexus_postgresql_local_enabled: false` and overriding connection vars.
- Compatibility hardening: write Nexus datastore config to both `{{ nexus_data_dir }}` and legacy `{{ nexus_install_dir }}/sonatype-work/nexus3` config paths so mixed launcher/runtime path behavior does not silently fall back to H2.

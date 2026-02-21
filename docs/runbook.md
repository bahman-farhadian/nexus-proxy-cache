# Runbook

## First-time bootstrap

1. Configure inventory:
```bash
nano inventories/host.yml
```

2. Create local tooling virtualenv:
```bash
make venv
source .venv/bin/activate
```

3. Ensure `nexus_hostname` is resolvable from clients and your operator machine (DNS or `/etc/hosts`).
If `nexus_tls_enabled` is true, ensure `nexus_tls_domain` DNS points to `nexus_public_ip`.

4. Create local admin password file:
```bash
cp .nexus_admin_password.example .nexus_admin_password
nano .nexus_admin_password
chmod 600 .nexus_admin_password
```
Keep the password as the first non-empty, non-comment line.
Nexus encryption key seed files are generated automatically on control host as `.nexus_secret_key`, `.nexus_secret_salt`, `.nexus_secret_iv` (all gitignored).

5. Create local PostgreSQL password file:
```bash
cp .nexus_db_password.example .nexus_db_password
nano .nexus_db_password
chmod 600 .nexus_db_password
```
Keep one password line. This is used for Nexus PostgreSQL datastore user.

6. Validate:
```bash
make help
make lint
ansible-playbook -i inventories/host.yml site.yml --syntax-check
ansible nexus -i inventories/host.yml -m ansible.builtin.ping
```

7. Deploy:
```bash
ansible-playbook -i inventories/host.yml site.yml
```

8. Verify API and services:
```bash
sudo systemctl status nexus --no-pager
sudo systemctl status nginx --no-pager
sudo systemctl status postgresql --no-pager
curl -sf http://repo.idops.local/service/rest/v1/status | jq
```
Replace URL/scheme if you changed hostname/ports or enabled TLS.
In TLS mode, also verify renewal timer: `sudo systemctl status certbot.timer --no-pager`.
Debian APT defaults include both `bookworm` (Debian 12) and `trixie` (Debian 13) upstream caches.

## Day-2 operations

### Restart Nexus
```bash
ansible nexus -i inventories/host.yml -b -m ansible.builtin.systemd_service -a "name=nexus state=restarted"
```

### Check Nexus service
```bash
ansible nexus -i inventories/host.yml -b -m ansible.builtin.systemd_service -a "name=nexus state=started"
```

### View logs on target
```bash
sudo journalctl -u nexus -n 200 --no-pager
sudo tail -n 200 /var/lib/nexus/log/nexus.log
```

## Upgrading Nexus version

1. Change `nexus_version` in `group_vars/all.yml`.
2. Optionally set `nexus_download_checksum`.
3. Run deploy again:
```bash
ansible-playbook -i inventories/host.yml site.yml
```

The role extracts the new version, repoints `/opt/nexus/current`, and restarts service if needed.

## Rollback approach

1. Set `nexus_version` back to previous known-good value.
2. Re-run deploy playbook.
3. Verify service and repository API health.

## Failure scenarios

- If admin password tasks fail and `/var/lib/nexus/admin.password` is missing, update `.nexus_admin_password` with the current known admin password.
- The role tries fallback `admin123`; if that also fails, reset Nexus admin credentials manually or reinitialize data on non-production nodes.
- For full reset on non-production nodes, clear both data locations before redeploy: `/var/lib/nexus/*` and `/opt/nexus/sonatype-work/nexus3/*`.
- If TLS mode is enabled, verify renewal automation with `systemctl status certbot.timer`.
- Let's Encrypt cannot issue certificates for raw IP addresses; use a DNS hostname for `nexus_tls_domain`.
- If APT group endpoint is unavailable, use per-upstream APT proxies on clients.
- If Nexus status still shows `Recommended Limits for H2` while `nexus_database_backend: postgresql`, verify both files exist with the same content:
  - `/var/lib/nexus/etc/fabric/nexus-store.properties`
  - `/opt/nexus/sonatype-work/nexus3/etc/fabric/nexus-store.properties`
  and confirm PostgreSQL connectivity/credentials in `.nexus_db_password`.
- If Nexus status still shows `Default Secret Encryption Key`, verify:
  - `nexus_manage_custom_encryption_key: true`
  - `/var/lib/nexus/etc/nexus-secrets.json` exists and is readable by `nexus`
  then rerun playbook to trigger re-encryption APIs again.

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

3. Ensure `nexus_hostname` is resolvable from clients and Nexus VM (DNS or `/etc/hosts`).

4. Create local admin password file:
```bash
cp .nexus_admin_password.example .nexus_admin_password
nano .nexus_admin_password
chmod 600 .nexus_admin_password
```
Keep a single password line in this file.

5. Validate:
```bash
make lint
ansible-playbook -i inventories/host.yml site.yml --syntax-check
ansible nexus -i inventories/host.yml -m ansible.builtin.ping
```

6. Deploy:
```bash
ansible-playbook -i inventories/host.yml site.yml
```

7. Verify API and services:
```bash
sudo systemctl status nexus --no-pager
sudo systemctl status nginx --no-pager
curl -sf http://repo.idops.local/service/rest/v1/status | jq
```
Replace URL if you changed `nexus_hostname` or `nexus_public_port`.

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
- If APT group endpoint is unavailable, use per-upstream APT proxies on clients.

# Runbook

## First-time bootstrap

1. Configure inventory:
```bash
vi inventories/dev/hosts.ini
```

2. Create local tooling virtualenv:
```bash
make venv
source .venv/bin/activate
```

3. Ensure `nexus_hostname` is resolvable from clients and Nexus VM (DNS or `/etc/hosts`).

4. Set and encrypt vault secrets:
```bash
vi group_vars/all/vault.yml
ansible-vault encrypt group_vars/all/vault.yml
```

5. Validate:
```bash
make lint
ansible-playbook -i inventories/dev/hosts.ini site.yml --syntax-check
```

6. Deploy:
```bash
ansible-playbook -i inventories/dev/hosts.ini site.yml --ask-vault-pass
```

## Day-2 operations

### Restart Nexus
```bash
ansible nexus -i inventories/dev/hosts.ini -b -m ansible.builtin.systemd_service -a "name=nexus state=restarted"
```

### Check Nexus service
```bash
ansible nexus -i inventories/dev/hosts.ini -b -m ansible.builtin.systemd_service -a "name=nexus state=started"
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
ansible-playbook -i inventories/dev/hosts.ini site.yml --ask-vault-pass
```

The role extracts the new version, repoints `/opt/nexus/current`, and restarts service if needed.

## Rollback approach

1. Set `nexus_version` back to previous known-good value.
2. Re-run deploy playbook.
3. Verify service and repository API health.

## Failure scenarios

- If admin password task fails and `admin.password` is missing, set `vault_nexus_admin_password` to current known admin password.
- If APT group endpoint is unavailable, use per-upstream APT proxies on clients.

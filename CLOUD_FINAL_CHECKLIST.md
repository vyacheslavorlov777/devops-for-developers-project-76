## Cloud Finalization Checklist (Yandex Cloud)

Use this checklist to finish strict cloud requirements for the project.

### 1) Create cloud resources

- 2 Ubuntu VMs for app (`app-1`, `app-2`) with public IPs
- 1 PostgreSQL cluster (managed) or 1 DB VM (`db-1`)
- 1 Application Load Balancer (L7) targeting both app VMs

### 2) Network and access rules

- VM security group:
  - inbound `22/tcp` from your public IP
  - inbound app port (`80/tcp`) only from LB security group
  - outbound all
- DB security group:
  - inbound `5432/tcp` (or managed PG port) only from app VM security group
  - no public DB access from internet
- LB security group:
  - inbound `80/tcp` (and optionally `443/tcp`) from internet

### 3) Update Ansible inventory

Edit `inventory/hosts.ini`:

```ini
[webservers]
app-1 ansible_host=<APP_1_PUBLIC_IP>
app-2 ansible_host=<APP_2_PUBLIC_IP>

[dbservers]
db-1 ansible_host=<DB_VM_PUBLIC_IP>

[webservers:vars]
ansible_user=ubuntu
ansible_ssh_private_key_file=/absolute/path/to/private/key

[dbservers:vars]
ansible_user=ubuntu
ansible_ssh_private_key_file=/absolute/path/to/private/key
```

If you use managed PostgreSQL, `dbservers` can be skipped for runtime (but keep DB vars in `group_vars/all.yml`).

### 4) Update DB variables

Edit `group_vars/all.yml`:

```yaml
redmine_db_adapter: "postgresql"
redmine_db_host: "<DB_HOST_OR_ENDPOINT>"
redmine_db_port: 5432
redmine_db_name: "redmine"
redmine_db_user: "redmine"
redmine_db_password: "<DB_PASSWORD>"
```

### 5) Run deployment

```bash
make install
make ping
make deploy-all
```

For managed PostgreSQL:
- use `make deploy` if DB is already provisioned externally

### 6) Validate result

- VM checks:
  - `ssh ubuntu@<APP_1_PUBLIC_IP>`
  - `ssh ubuntu@<APP_2_PUBLIC_IP>`
- App checks:
  - `http://<APP_1_PUBLIC_IP>`
  - `http://<APP_2_PUBLIC_IP>`
- LB check:
  - `http://<LOAD_BALANCER_PUBLIC_ADDRESS>`
  - refresh multiple times, requests should be served by both app VMs

### 7) Submission evidence

Prepare:
- screenshot of cloud VMs
- screenshot of LB target group/backends healthy
- screenshot of DB cluster settings and restricted access
- terminal output with successful `make deploy-all`

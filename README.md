### Hexlet tests and linter status:
[![Actions Status](https://github.com/Vyacheslavorlov777/devops-for-developers-project-76/actions/workflows/hexlet-check.yml/badge.svg)](https://github.com/Vyacheslavorlov777/devops-for-developers-project-76/actions)

## Redmine Deployment

This project deploys Redmine in Docker on two app servers and exposes it through
an Nginx load balancer and domain.

Live URL: [https://myproj76.ru](https://myproj76.ru)

## Current project setup (actual)

Production-like stack for this project is split into two parts:

- Local infrastructure (Multipass on your machine):
  - `app-1`, `app-2` - Redmine app nodes
  - `db-1` - PostgreSQL
  - `lb-1` - Nginx load balancer
- Public relay:
  - external VPS with public IP and Nginx
  - domain `myproj76.ru` points to VPS
  - reverse SSH tunnel forwards VPS traffic to local `lb-1`

### Important limitation

App VMs and DB are local, so they depend on the host device and network:

- if your laptop/PC is off, local VMs are unavailable;
- if reverse tunnel is down, public access from the internet is unavailable;
- internet visibility is provided by relay, but service data plane is still local.

### Prerequisites

- Three Ubuntu servers accessible over SSH (`app-1`, `app-2`, `db-1`)
- Optional fourth Ubuntu server for local load balancer (`lb-1`)
- Ansible installed on local machine

### 1. Install dependencies

```bash
make install
```

### 2. Prepare inventory and variables

Edit `inventory.ini` in the project root and set host addresses/users for:
- `webservers` (`web-1`, `web-2`)
- `dbservers` (`db-1`)
- `lbservers` (`lb-1`)

Set shared variables in `group_vars/all.yml`, especially:
- `redmine_port` - external app port used by app containers and load balancer
- DB non-secret variables (`redmine_db_host`, `redmine_db_port`, `redmine_db_name`, `redmine_db_user`)

Store DB password in encrypted Vault files:
- `group_vars/webservers/vault.yml`
- `group_vars/dbservers/vault.yml`

And expose decrypted values via:
- `group_vars/webservers/vars.yml`
- `group_vars/dbservers/vars.yml`

Create a local vault password file (not committed):

```bash
printf 'your-strong-vault-password\n' > .vault_pass
chmod 600 .vault_pass
```

### 3. Check connectivity

```bash
make ping-all
```

### 4. Prepare servers (one-time)

```bash
make prepare
```

This installs pip/docker dependencies through Galaxy roles (`playbook-prepare.yml`).

### 5. Deploy database

```bash
make deploy-db
```

### 6. Deploy Redmine app

```bash
make deploy
```

`make deploy` runs root `playbook.yml` and only deploys application on `webservers`
without server preparation changes.

### 7. Deploy/reload load balancer

```bash
make deploy-lb
```

### 8. Full deploy

```bash
make deploy-all
```

### 9. HTTPS on domain

Public HTTPS is terminated on the external VPS relay (Nginx + Let's Encrypt).

Example commands on VPS:

```bash
sudo apt-get update
sudo apt-get install -y certbot python3-certbot-nginx
sudo certbot --nginx -d myproj76.ru --non-interactive --agree-tos --register-unsafely-without-email --redirect
```

After certificate issue, verify:

```bash
curl -I https://myproj76.ru
```

### 10. Datadog monitoring on webservers

Datadog agent is installed during app deploy (`playbook.yml`) only for `webservers`.

Required secret:
- `vault_datadog_api_key` in `group_vars/webservers/vault.yml` (encrypted with Ansible Vault)

Configured check:
- `http_check` to `http://127.0.0.1:{{ redmine_port }}/` on each app server

Set or update secrets:

```bash
make vault-edit-web
make vault-view-web
```

### Additional commands

```bash
make syntax-check
make lint
make prepare
make deploy-db
make deploy
make deploy-lb
make deploy-all
make run
make status
make test
make stop
make vault-edit-web
make vault-view-web
make vault-edit-db
make vault-view-db
```

### Public relay commands (for local VM exposure)

- `make run` - start reverse relay tunnel (`Mac -> VPS -> lb-1`)
- `make status` - check relay process and HTTP status codes
- `make test` - run external HTTPS checks for `myproj76.ru`
- `make stop` - stop relay tunnel

### Project structure

- `playbook.yml` — Redmine deploy playbook (`webservers`)
- `playbook-prepare.yml` — server preparation playbook (`hosts: all`)
- `inventory.ini` — inventory with `webservers` group
- `group_vars/all.yml` — shared variables
- `playbook-db.yml` — PostgreSQL setup for Redmine database
- `playbook-lb.yml` — Nginx load balancer setup
- `site.yml` — full deployment (database + app + load balancer)
- `roles/redmine/tasks/main.yml` — Docker install and container deployment
- `roles/redmine/templates/redmine.env.j2` — container environment file template
- `roles/postgresql/tasks/main.yml` — PostgreSQL installation and DB initialization
- `roles/loadbalancer/tasks/main.yml` — Nginx installation and reverse proxy setup
- `Makefile` — shortcuts for install, ping, deploy, lint, syntax check
- `.ansible-lint` — linter configuration
- `inventory/hosts.ini.example` — inventory example
- `group_vars/all.yml.example` — project variables example
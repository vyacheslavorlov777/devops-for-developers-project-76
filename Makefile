SHELL := /bin/bash

DOMAIN ?= myproj76.ru
VPS_IP ?= 168.222.143.207
SSH_KEY ?= /Users/mamboota/.ssh/multipass_ansible
LB_ORIGIN ?= 192.168.2.5:80
SSH_USER ?= ubuntu
APP1_IP ?= 192.168.2.2
APP2_IP ?= 192.168.2.3
LB_IP ?= 192.168.2.5
VAULT_PASSWORD_FILE ?= .vault_pass
VAULT_ARGS ?= --vault-password-file $(VAULT_PASSWORD_FILE)

.PHONY: install ping ping-all prepare deploy deploy-db deploy-lb deploy-all lint syntax-check vault-edit-web vault-view-web vault-edit-db vault-view-db run stop status logs test

install:
	ansible-galaxy install -r requirements.yml

ping:
	ansible webservers -m ping

ping-all:
	ansible all -m ping

prepare:
	ansible-playbook playbook-prepare.yml

deploy:
	ansible-playbook $(VAULT_ARGS) playbook.yml

deploy-db:
	ansible-playbook $(VAULT_ARGS) playbook-db.yml

deploy-lb:
	ansible-playbook playbook-lb.yml

deploy-all:
	ansible-playbook $(VAULT_ARGS) site.yml

lint:
	ansible-lint playbook-prepare.yml playbook.yml playbook-db.yml playbook-lb.yml site.yml

syntax-check:
	ansible-playbook --syntax-check playbook-prepare.yml
	ansible-playbook $(VAULT_ARGS) --syntax-check playbook.yml
	ansible-playbook $(VAULT_ARGS) --syntax-check playbook-db.yml
	ansible-playbook --syntax-check playbook-lb.yml
	ansible-playbook $(VAULT_ARGS) --syntax-check site.yml

vault-edit-web:
	ansible-vault edit $(VAULT_ARGS) group_vars/webservers/vault.yml

vault-view-web:
	ansible-vault view $(VAULT_ARGS) group_vars/webservers/vault.yml

vault-edit-db:
	ansible-vault edit $(VAULT_ARGS) group_vars/dbservers/vault.yml

vault-view-db:
	ansible-vault view $(VAULT_ARGS) group_vars/dbservers/vault.yml

run:
	@echo "Preparing local app/lb services before tunnel ..."
	@for host in $(APP1_IP) $(APP2_IP); do \
		echo "Ensuring Docker is up on $$host ..."; \
		ssh -i "$(SSH_KEY)" -o StrictHostKeyChecking=no $(SSH_USER)@$$host \
			"sudo systemctl start docker.socket || true; sudo systemctl start docker || true"; \
	done
	@echo "Reloading nginx on $(LB_IP) ..."
	@ssh -i "$(SSH_KEY)" -o StrictHostKeyChecking=no $(SSH_USER)@$(LB_IP) \
		"sudo systemctl reload nginx || sudo systemctl restart nginx"
	@echo "Waiting for local LB to return 200 ..."
	@ok=0; \
	for i in {1..15}; do \
		code=$$(ssh -i "$(SSH_KEY)" -o StrictHostKeyChecking=no $(SSH_USER)@$(LB_IP) \
			"curl --max-time 5 -s -o /dev/null -w '%{http_code}' http://127.0.0.1/"); \
		echo "$$i:$$code"; \
		if [[ "$$code" == "200" ]]; then ok=1; break; fi; \
		sleep 1; \
	done; \
	if [[ $$ok -ne 1 ]]; then \
		echo "Local LB is not healthy (expected 200)."; \
		exit 1; \
	fi
	@echo "Starting reverse relay tunnel to $(VPS_IP) ..."
	@pkill -f "root@$(VPS_IP)" 2>/dev/null || true
	@nohup ssh -i "$(SSH_KEY)" \
		-o ExitOnForwardFailure=yes \
		-o ServerAliveInterval=30 \
		-o ServerAliveCountMax=3 \
		-o StrictHostKeyChecking=no \
		-N -R 127.0.0.1:18080:$(LB_ORIGIN) \
		root@$(VPS_IP) >/tmp/vps-relay.log 2>&1 &
	@sleep 2
	@pgrep -fl "root@$(VPS_IP)" >/dev/null && \
		echo "Relay tunnel is running." || \
		(echo "Relay tunnel failed to start. Check /tmp/vps-relay.log"; exit 1)

stop:
	@echo "Stopping reverse relay tunnel to $(VPS_IP) ..."
	@pkill -f "root@$(VPS_IP)" 2>/dev/null || true
	@sleep 1
	@if pgrep -fl "root@$(VPS_IP)" >/dev/null; then \
		echo "Relay tunnel is still running."; \
		exit 1; \
	else \
		echo "Relay tunnel stopped."; \
	fi

status:
	@echo "Relay process:"
	@pgrep -fl "root@$(VPS_IP)" || echo "not running"
	@echo "Domain check:"
	@curl --max-time 8 -s -o /dev/null -w "https://$(DOMAIN) -> %{http_code}\n" "https://$(DOMAIN)" || true
	@echo "VPS relay check:"
	@curl --max-time 8 -s -o /dev/null -w "http://$(VPS_IP) -> %{http_code}\n" "http://$(VPS_IP)" || true

logs:
	@echo "Last relay logs (/tmp/vps-relay.log):"
	@tail -n 40 /tmp/vps-relay.log 2>/dev/null || echo "no log file"

test:
	@echo "Testing https://$(DOMAIN) ..."
	@echo "Waiting for first healthy response ..."
	@ready=0; \
	for i in {1..15}; do \
		code=$$(curl --max-time 8 -s -o /dev/null -w "%{http_code}" "https://$(DOMAIN)"); \
		echo "warmup $$i:$$code"; \
		if [[ "$$code" == "200" ]]; then ready=1; break; fi; \
		sleep 1; \
	done; \
	if [[ $$ready -ne 1 ]]; then \
		echo "FAIL: endpoint did not become healthy during warm-up"; \
		exit 1; \
	fi
	@ok=1; \
	for i in {1..10}; do \
		code=$$(curl --max-time 8 -s -o /dev/null -w "%{http_code}" "https://$(DOMAIN)"); \
		echo "$$i:$$code"; \
		if [[ "$$code" != "200" ]]; then ok=0; fi; \
		sleep 1; \
	done; \
	if [[ $$ok -eq 1 ]]; then \
		echo "PASS: 10/10 responses are HTTP 200"; \
	else \
		echo "FAIL: non-200 response detected"; \
		exit 1; \
	fi
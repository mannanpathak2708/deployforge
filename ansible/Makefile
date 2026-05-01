# ============================================================================
#  Makefile — Ansible convenience targets for DeployForge.
#
#  Common flow:
#    make ping          (verify SSH to all 3 nodes)
#    make bootstrap     (run site.yml — install kubeadm cluster)
#    make kubeconfig    (copy admin kubeconfig to your Mac)
#    make deploy-app    (deploy the Spring Boot app)
#    make smoke         (verify everything works)
# ============================================================================

.DEFAULT_GOAL := help
SHELL := /bin/bash

GREEN  := \033[0;32m
YELLOW := \033[0;33m
RED    := \033[0;31m
RESET  := \033[0m

.PHONY: help
help: ## Show this help
	@echo "DeployForge Ansible — available targets:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  $(GREEN)%-15s$(RESET) %s\n", $$1, $$2}'

.PHONY: collections
collections: ## Install required Ansible collections (one time)
	ansible-galaxy collection install kubernetes.core ansible.posix community.general

.PHONY: ping
ping: ## Test SSH to every node
	ansible all -m ping

.PHONY: facts
facts: ## Gather and print facts about all nodes
	ansible all -m setup -a 'filter=ansible_distribution*'

.PHONY: bootstrap
bootstrap: collections ## Run site.yml — install kubeadm cluster end-to-end (~15-20 min)
	ansible-playbook site.yml

.PHONY: bootstrap-check
bootstrap-check: ## Dry-run site.yml without making changes
	ansible-playbook site.yml --check --diff

.PHONY: kubeconfig
kubeconfig: ## Copy admin kubeconfig to ~/.kube/deployforge.config
	ansible-playbook fetch-kubeconfig.yml
	@echo -e "$(GREEN)Run: export KUBECONFIG=~/.kube/deployforge.config$(RESET)"

.PHONY: deploy-app
deploy-app: ## Deploy the Spring Boot app (re-run after code changes)
	ansible-playbook deploy-app.yml -e db_password=$${DB_PASSWORD:-changeme123}

.PHONY: smoke
smoke: ## Verify the cluster + app are healthy
	ansible-playbook smoke-test.yml

.PHONY: nodes
nodes: ## kubectl get nodes (run on master)
	ansible master -m shell -a 'kubectl get nodes -o wide'

.PHONY: pods
pods: ## kubectl get pods -A (run on master)
	ansible master -m shell -a 'kubectl get pods -A'

.PHONY: logs-app
logs-app: ## Tail the application logs
	ansible master -m shell -a 'kubectl logs -n deployforge -l app=taskmanager --tail=100'

.PHONY: grafana-port
grafana-port: ## Print Grafana access info
	@echo "Grafana is at: http://$$(ansible master -m shell -a 'curl -s http://169.254.169.254/latest/meta-data/public-ipv4' --one-line | tail -c +3 | cut -d'|' -f4-):30030"
	@echo "Login: admin / admin"

.PHONY: shell-master
shell-master: ## SSH to the master
	@ansible master -m shell -a 'echo "Use: cd ../terraform && make ssh-master"'

.PHONY: clean
clean: ## Remove fact cache and join command file
	rm -rf /tmp/ansible-facts join-command.sh

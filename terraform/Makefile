# ============================================================================
#  Makefile — convenience targets so you don't have to remember Terraform's CLI.
#
#  Common flow:
#    make init        (once, after first clone)
#    make plan        (preview changes before applying)
#    make apply       (build the infra)
#    make ssh-master  (jump on the master)
#    make destroy     (TEAR DOWN — saves $3/day)
#
#  Run `make help` to see all targets.
# ============================================================================

.DEFAULT_GOAL := help
SHELL := /bin/bash

# Colours for terminal output
GREEN  := \033[0;32m
YELLOW := \033[0;33m
RED    := \033[0;31m
RESET  := \033[0m

.PHONY: help
help: ## Show this help
	@echo "DeployForge Terraform — available targets:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  $(GREEN)%-15s$(RESET) %s\n", $$1, $$2}'

.PHONY: init
init: ## Initialise Terraform — downloads providers (run once)
	@if [ ! -f terraform.tfvars ]; then \
		echo -e "$(YELLOW)terraform.tfvars not found — copying from example$(RESET)"; \
		cp terraform.tfvars.example terraform.tfvars; \
		echo -e "$(YELLOW)Review terraform.tfvars before running 'make plan'$(RESET)"; \
	fi
	terraform init

.PHONY: validate
validate: ## Check syntax without contacting AWS
	terraform fmt -check -recursive
	terraform validate

.PHONY: plan
plan: ## Show what Terraform WILL do — review before apply
	terraform plan -out=tfplan

.PHONY: apply
apply: ## Build the infrastructure (~10 minutes)
	@echo -e "$(YELLOW)This will create AWS resources that cost ~\$$3/day if left running.$(RESET)"
	@echo -e "$(YELLOW)Press Ctrl+C in 5 seconds to abort.$(RESET)"
	@sleep 5
	terraform apply tfplan || terraform apply
	@echo -e "$(GREEN)Done. Useful next commands:$(RESET)"
	@echo -e "  make ssh-master      — SSH to the master"
	@echo -e "  make inventory       — write Ansible inventory"
	@echo -e "  make outputs         — show all outputs"

.PHONY: outputs
outputs: ## Print all Terraform outputs
	terraform output

.PHONY: ssh-master
ssh-master: ## SSH to the master node
	@$$(terraform output -raw ssh_master)

.PHONY: ssh-worker-1
ssh-worker-1: ## SSH to worker 1
	@ssh -i ~/.ssh/$$(terraform output -raw key_name 2>/dev/null || echo deployforge-key).pem ubuntu@$$(terraform output -json worker_public_ips | jq -r '.[0]')

.PHONY: inventory
inventory: ## Write Ansible inventory to ../ansible/inventory.ini
	@mkdir -p ../ansible
	@terraform output -raw ansible_inventory > ../ansible/inventory.ini
	@echo -e "$(GREEN)Wrote ../ansible/inventory.ini$(RESET)"
	@cat ../ansible/inventory.ini

.PHONY: ecr-login
ecr-login: ## docker login to ECR (needed before manual pushes)
	aws ecr get-login-password --region $$(terraform output -raw aws_region) | \
		docker login --username AWS --password-stdin $$(terraform output -raw ecr_registry)

.PHONY: cost
cost: ## Estimated monthly cost if left running (rough)
	@echo "Approximate cost (us-east-1, on-demand):"
	@echo "  3 × t3.medium @ \$$0.0416/hr = \$$3.00/day = \$$90/month"
	@echo "  3 × 30GB gp3   @ \$$0.08/GB-month = \$$7.20/month"
	@echo "  ECR storage    : ~\$$0.10/month for the image"
	@echo "  Data transfer  : negligible (<\$$1/month for course usage)"
	@echo "  TOTAL if left running 24/7: ~\$$98/month"
	@echo "  TOTAL if you destroy nightly: ~\$$5-10 over the project"

.PHONY: destroy
destroy: ## TEAR DOWN everything — do this between sessions
	@echo -e "$(RED)This will DELETE all DeployForge infrastructure.$(RESET)"
	@echo -e "$(RED)EBS volumes will be wiped — your kubeadm cluster state goes too.$(RESET)"
	@read -p "Type 'destroy' to confirm: " confirm && [ "$$confirm" = "destroy" ]
	terraform destroy

.PHONY: state-list
state-list: ## List everything Terraform is tracking
	terraform state list

.PHONY: clean
clean: ## Remove local plan files (does NOT touch AWS)
	rm -f tfplan
	@echo "Removed local tfplan. Use 'make destroy' to actually delete AWS resources."

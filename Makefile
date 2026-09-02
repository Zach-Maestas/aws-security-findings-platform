TERRAFORM_DIR := infrastructure/terraform

# ==============================================================================
# Primary deploy path is the GitHub Actions "Deploy Infrastructure" workflow
# (workflow_dispatch), authenticated via OIDC — no stored AWS credentials.
#
# `deploy`/`destroy` below are a manual break-glass fallback for when Actions
# is unavailable. They require your own local AWS credentials with apply-level
# permissions on this account — that's a deliberate exception to the
# no-stored-credentials posture the OIDC setup exists to enforce, so use them
# only when you actually need to bypass the pipeline.
# ==============================================================================

deploy:
	cd $(TERRAFORM_DIR) && terraform init && terraform apply -auto-approve && terraform fmt -recursive

destroy:
	cd $(TERRAFORM_DIR) && terraform destroy -auto-approve

fmt:
	cd $(TERRAFORM_DIR) && terraform fmt -recursive

validate:
	cd $(TERRAFORM_DIR) && terraform fmt -check -recursive && terraform validate

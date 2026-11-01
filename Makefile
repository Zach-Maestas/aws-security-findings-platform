TERRAFORM_DIR := infrastructure/terraform
APP_DIR := application

.PHONY: help app-fix app-check test-db test-db-down test tf-fmt tf-validate deploy destroy

# A bare `make` prints help instead of running the first target (deploy).
.DEFAULT_GOAL := help

help:
	@echo "App:       app-fix  app-check  test-db  test-db-down  test"
	@echo "Terraform: tf-fmt  tf-validate  deploy  destroy (break-glass only)"

# ==============================================================================
# Application
# ==============================================================================

# Auto-fix lint issues and format code (changes files)
app-fix:
	cd $(APP_DIR) && uv run ruff check --fix . && uv run ruff format .

# Same checks CI runs (changes nothing)
app-check:
	cd $(APP_DIR) && uv run ruff check . && uv run ruff format --check .

# Start the disposable test database and wait until it's healthy
test-db:
	cd $(APP_DIR) && docker compose --profile test up -d --wait test-db

# Stop the test database (its tmpfs data is discarded)
test-db-down:
	cd $(APP_DIR) && docker compose --profile test down

# Run all tests (starts test-db first)
test: test-db
	cd $(APP_DIR) && uv run pytest

# ==============================================================================
# Terraform
# ==============================================================================

tf-fmt:
	cd $(TERRAFORM_DIR) && terraform fmt -recursive

tf-validate:
	cd $(TERRAFORM_DIR) && terraform fmt -check -recursive && terraform validate

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
	cd $(TERRAFORM_DIR) && terraform fmt -recursive && terraform init && terraform apply -auto-approve

destroy:
	cd $(TERRAFORM_DIR) && terraform destroy -auto-approve

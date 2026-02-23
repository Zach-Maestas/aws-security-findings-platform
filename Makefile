TERRAFORM_DIR := infrastructure/terraform
SCRIPTS_DIR   := infrastructure/scripts/deploy

deploy:
	cd $(TERRAFORM_DIR) && terraform init && terraform apply -auto-approve && terraform fmt -recursive
	bash $(SCRIPTS_DIR)/01_build_and_push_images.sh
	bash $(SCRIPTS_DIR)/02_run_db_init.sh
	bash $(SCRIPTS_DIR)/03_scale_ecs_service.sh 1

destroy:
	bash $(SCRIPTS_DIR)/03_scale_ecs_service.sh 0
	cd $(TERRAFORM_DIR) && terraform destroy -auto-approve

fmt:
	cd $(TERRAFORM_DIR) && terraform fmt -recursive

validate:
	cd $(TERRAFORM_DIR) && terraform fmt -check -recursive && terraform validate

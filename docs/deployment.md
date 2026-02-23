# Deployment Guide ⚙️

Detailed steps for deploying, verifying, and tearing down the infrastructure. For a quick overview, see the [README](../README.md#quick-start).

---

## Prerequisites

### Required Tools

| Tool | Minimum Version | Verify |
|------|----------------|--------|
| AWS CLI | v2 | `aws --version` |
| Terraform | >= 1.0 | `terraform --version` |
| Docker | with buildx | `docker buildx version` |
| GNU Make | any | `make --version` |

### AWS Account Setup

1. **AWS CLI configured** — run `aws sts get-caller-identity` to confirm.
2. **Required permissions** — your IAM identity needs access to manage:
   - VPC, Subnets, Security Groups, NAT/Internet Gateways
   - ECS (clusters, services, task definitions)
   - ECR (repositories, image push)
   - RDS (instances, subnet groups)
   - ALB (load balancers, target groups, listeners)
   - ACM (certificates)
   - Secrets Manager
   - IAM (roles, policies)
   - CloudWatch Logs
   - Route 53 (DNS records)

3. **Route 53 hosted zone** — a hosted zone must exist for your domain. The ACM module uses DNS validation against it.

4. **Terraform state backend** — state is stored locally by default. For shared/remote state, configure an S3 backend in `infrastructure/terraform/main.tf`.

---

## Deployment

### One-Command Deploy

```bash
make deploy
```

This runs the following steps in order:

| Step | Make Target | What It Does |
|------|------------|--------------|
| 1 | `terraform-apply` | Provisions all AWS resources (VPC, ECS, RDS, ALB, ECR, etc.) |
| 2 | `build` | Builds API and DB init Docker images, pushes to ECR |
| 3 | `db-init` | Runs a one-off ECS task to initialize the RDS schema |
| 4 | `scale-up` | Scales the ECS API service to 1 running task |

### Step-by-Step (Manual)

If you need to run individual steps or debug:

```bash
# 1. Initialize and apply Terraform
make terraform-apply

# 2. Build and push container images to ECR
make build

# 3. Run database initialization
make db-init

# 4. Start the API service
make scale-up
```

---

## Verification

After deployment completes, verify the stack:

```bash
# Check service status
make status

# Test endpoints
curl https://api.zachmaestas-capstone.com/health
curl https://api.zachmaestas-capstone.com/ready
curl https://api.zachmaestas-capstone.com/items
```

### What to check in AWS Console
- **ECS** — cluster shows 1 running task, no stopped tasks with errors
- **ALB** — target group shows healthy targets
- **RDS** — instance status is "Available"
- **CloudWatch Logs** — `/ecs/devsecops-security-ops-api-task` shows Flask startup logs

---

## Teardown

```bash
make destroy
```

This scales down the ECS service, then runs `terraform destroy` to remove all resources.

### Partial Teardown Failures

If `make destroy` fails partway (e.g., ECS cluster already gone):

```bash
# Skip scale-down, go straight to terraform destroy
make terraform-destroy
```

### ECR Repositories

ECR repos are configured with `force_delete = true`, so they will be destroyed even if they still contain images.

---

## Redeployment (Code Changes Only)

If you've changed application code but infrastructure is still up:

```bash
make redeploy
```

This rebuilds images, scales down, and scales back up — without re-running Terraform.

---

## Troubleshooting

| Symptom | Check | Fix |
|---------|-------|-----|
| ECS task keeps stopping | `make logs` or CloudWatch `/ecs/devsecops-security-ops-api-task` | Check container exit code and error message |
| ALB target unhealthy | Target group health check in AWS Console | Verify `/health` returns 200, security groups allow ALB → ECS |
| DB connection refused | ECS task logs for connection errors | Check RDS security group allows inbound from ECS SG on port 5432 |
| Terraform apply fails | Terraform error output | Common: state drift, resource limits, permission denied |
| ECR push fails | Docker login and buildx errors | Re-run `aws ecr get-login-password` or check IAM ECR permissions |

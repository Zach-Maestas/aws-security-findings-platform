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

4. **Terraform state backend** — remote state is stored in S3 with DynamoDB locking. The backend is bootstrapped via `infrastructure/terraform/backend-state-init/`.

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
- **CloudWatch Logs** — `/ecs/secops-pipeline-app` shows Flask startup logs

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

## CI/CD Deployment (GitHub Actions)

Infrastructure can also be deployed automatically through GitHub Actions using OIDC authentication — no stored AWS credentials.

### Pipeline Strategy

| Workflow | Trigger | Role | Purpose |
|----------|---------|------|---------|
| `pr-checks.yml` | Pull request to `main` | `secops-pipeline-github-actions-plan` (read-only) | Security scans + `terraform plan` |
| `deploy.yml` | Manual dispatch (or merge to `main`) | `secops-pipeline-github-actions-deploy` (write) | `terraform apply` + build + deploy |

### Deploy Workflow Steps

```
OIDC Auth → Terraform Apply → Docker Build & Push → DB Init → Scale Up ECS
```

1. **Authenticate** — GitHub Actions requests an OIDC token, AWS STS exchanges it for temporary credentials scoped to the deploy role
2. **Terraform Apply** — provisions all infrastructure (VPC, ECS, RDS, ALB, ECR, etc.)
3. **Build & Push** — builds Docker images and pushes to ECR
4. **DB Init** — runs a one-off ECS task to initialize the database schema
5. **Scale Up** — sets the ECS API service desired count to 1

### Enabling Auto-Deploy on Merge

The deploy workflow is configured for manual dispatch (`workflow_dispatch`). To enable auto-deploy when PRs merge to `main`, uncomment the `push` trigger in `.github/workflows/deploy.yml`:

```yaml
on:
  push:
    branches: [main]
    paths:
      - 'infrastructure/terraform/**'
      - 'application/**'
      - '.github/workflows/deploy.yml'
```

The `paths` filter ensures deploys only trigger when infrastructure or application code changes — not on documentation or CI config edits.

### Security Controls

- **OIDC federation** — no long-lived AWS credentials stored in GitHub
- **Separate roles** — plan role is read-only, deploy role has write access with a permissions boundary
- **Permissions boundary** — caps what the deploy role and any roles it creates can do, preventing privilege escalation
- **PR gates** — security scans must pass before `terraform plan` runs; deploy only happens after merge

---

## Troubleshooting

| Symptom | Check | Fix |
|---------|-------|-----|
| ECS task keeps stopping | `make logs` or CloudWatch `/ecs/secops-pipeline-app` | Check container exit code and error message |
| ALB target unhealthy | Target group health check in AWS Console | Verify `/health` returns 200, security groups allow ALB → ECS |
| DB connection refused | ECS task logs for connection errors | Check RDS security group allows inbound from ECS SG on port 5432 |
| Terraform apply fails | Terraform error output | Common: state drift, resource limits, permission denied |
| ECR push fails | Docker login and buildx errors | Re-run `aws ecr get-login-password` or check IAM ECR permissions |

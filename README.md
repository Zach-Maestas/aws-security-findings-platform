# AWS Cloud Security Operations & DevSecOps Project

A production-patterned AWS infrastructure project demonstrating cloud security engineering: secure networking, least-privilege IAM, secrets management, containerized deployment, monitoring/logging, detection and incident response, and DevSecOps pipeline security.

Built to be deployed, torn down, and redeployed from a single command.

## Architecture

![Architecture Diagram](./docs/screenshots/architecture-diagram.png)

### Components
| Layer | Service | Purpose |
|-------|---------|---------|
| Networking | VPC, Public/Private Subnets, NAT Gateway | Network isolation — compute and data in private subnets |
| Compute | ECS Fargate | Serverless container orchestration |
| Load Balancing | ALB + ACM | HTTPS termination with valid TLS certificate |
| Data | RDS PostgreSQL | Managed relational database in private subnet |
| Secrets | AWS Secrets Manager | Runtime credential injection, no plaintext secrets |
| Registry | ECR | Private container image storage |
| Observability | CloudWatch Logs | ECS, RDS PostgreSQL, VPC Flow Logs, CloudTrail |
| Detection | GuardDuty, Security Hub | Automated threat detection and findings aggregation |
| Response | EventBridge, Lambda, SNS | Automated remediation and alerting |
| CI/CD | GitHub Actions | OIDC auth, security scanning, automated deployment |

## Security Controls

| Control | Implementation | Evidence |
|---------|---------------|----------|
| Network isolation | ECS tasks and RDS in private subnets, ALB in public | Security group rules in Terraform |
| Least-privilege IAM | Scoped execution role per service, permissions boundaries | IAM policy snippets |
| Secrets management | DB credentials via Secrets Manager, injected at runtime | Task definition config |
| TLS/HTTPS | ALB listener with ACM certificate | ALB listener configuration |
| No broad ingress | Security groups scoped to specific ports and sources | SG rule audit |
| Non-root container | Application runs as non-root user | Dockerfile USER directive |
| Audit logging | CloudTrail API logging, RDS query logging, VPC Flow Logs | CloudWatch log groups |
| Threat detection | GuardDuty + Security Hub | Enabled dashboards |
| Automated response | EventBridge → Lambda remediation for IAM escalation and SG misconfig | Incident reports with timelines |
| Pipeline security | Gitleaks, Checkov, Trivy scans gate all PRs | Pass/fail screenshots |
| OIDC authentication | GitHub Actions authenticates via OIDC, no stored credentials | Trust policy + permissions boundary |

## Quick Start

### Prerequisites
- AWS CLI configured with appropriate credentials
- Terraform >= 1.0
- Docker with buildx support
- GNU Make

### Deploy
```bash
make deploy
```
This runs: `terraform apply` → `build & push images` → `DB init` → `scale up ECS service`

### Verify
```bash
curl https://api.zachmaestas-capstone.com/health
curl https://api.zachmaestas-capstone.com/ready
```

### Destroy
```bash
make destroy
```

## Project Phases

### Phase 1: Secure Baseline Infrastructure — ✅ Complete
Reproducible Terraform deployment producing a working HTTPS endpoint: ALB → ECS Fargate → RDS, with Secrets Manager integration and least-privilege IAM.

Key work:
- VPC with public/private subnet isolation across availability zones
- ECS Fargate with task-level secrets injection
- RDS PostgreSQL with security group scoped access
- Bootstrap method using ECS db-init task for repeatable teardown/rebuild

### Phase 2: Cloud Security — Detection, Monitoring, and Incident Response — ✅ Complete
Demonstrate operational security capabilities: detect threats, investigate findings, and respond to incidents.

Key work:
- CloudTrail enabled and queryable for audit trails
- GuardDuty for threat detection with Security Hub aggregation
- CloudWatch log organization for audit and investigation
- Automated response via EventBridge and Lambda
- Alerting via SNS
- Simulated security incident with full detect → investigate → respond lifecycle
- Written incident narrative documenting detection, response, and lessons learned
- Python scripting for detection and triage automation

### Phase 3: DevSecOps — Pipeline Security Gates — ✅ Complete
Shift security left by embedding scanning and policy enforcement into the development workflow.

Key work:
- GitHub Actions with OIDC-based AWS authentication (no stored credentials)
- IaC scanning with Checkov (static analysis on Terraform)
- Container image scanning with Trivy for known CVEs
- Secret detection with Gitleaks across full git history
- Pipeline gates that block PR merges on security failures
- Vulnerability caught by scanner → documented fix → pipeline passes
- Permissions boundary on deploy role preventing privilege escalation
- RDS PostgreSQL logging and VPC Flow Logs for observability

## Evidence

Evidence artifacts for all phases are in [`docs/`](docs/) — see [Security Design](docs/security.md) and [Incident Reports](docs/incident-reports.md).

## Known Limitations

- Single environment (dev) — multi-environment separation is out of scope for this project
- ECR repository and ECS cluster names are hardcoded in deployment scripts
- Cost-optimized for portfolio use — designed for full teardown/rebuild, not persistent uptime

## Tech Stack

| Tool | Version | Purpose |
|------|---------|---------|
| Terraform | >= 1.0 | Infrastructure as Code |
| AWS ECS Fargate | - | Container orchestration |
| Flask + Gunicorn | Python 3.13 | API application |
| PostgreSQL | 17 | Relational database (RDS) |
| Docker | buildx | Container builds |
| GitHub Actions | - | CI/CD with OIDC authentication |
| Checkov | - | IaC security scanning |
| Trivy | - | Container vulnerability scanning |
| Gitleaks | - | Secret detection |

## Documentation

- [Deployment Guide](docs/deployment.md) — deploy, verify, teardown, CI/CD, and troubleshooting
- [Security Design](docs/security.md) — security controls, IAM design, pipeline gates, and trade-off rationale
- [Incident Reports](docs/incident-reports.md) — simulated security incidents with detection and response evidence

## Repository Structure

```
.
├── application/
│   └── backend/              # Flask API (Dockerfile, app.py, Gunicorn)
├── docs/                     # Security design, incident narratives, evidence
├── infrastructure/
│   ├── scripts/
│   │   ├── aws-lambda/       # Python Lambda functions (IAM revoke, SG revoke)
│   │   ├── db-init/          # DB initialization container
│   │   └── deploy/           # Build, init, and scale scripts
│   └── terraform/
│       ├── backend-state-init/   # Bootstrap for remote state (S3 + DynamoDB)
│       ├── ci-oidc/              # GitHub Actions OIDC federation
│       └── modules/              # network, app, data, secrets, acm, security-ops
├── .github/
│   └── workflows/
│       ├── pr-checks.yml         # Security scans + terraform plan on PRs
│       └── deploy.yml            # Build + deploy on merge/dispatch
├── Makefile                  # Deploy/destroy orchestration
└── README.md
```

## Related Projects

This project builds on [Secure AWS Architecture Capstone](https://github.com/Zach-Maestas/secure-aws-architecture-capstone), which established the foundational VPC architecture and EC2-based deployment. This project evolved that baseline to ECS Fargate with secrets injection, and adds security operations and DevSecOps capabilities.

# AWS Security Findings Platform

A production-oriented cloud security findings and remediation platform: detects risky AWS activity, records and manages findings through a backend API, and performs reliable automated remediation. Combines backend software engineering (Python/FastAPI, PostgreSQL, Redis, Go workers) with infrastructure/platform engineering (AWS, Terraform, CI/CD, eventually Kubernetes/EKS).

Formerly "AWS Cloud Security Operations & DevSecOps Project" — renamed to match the direction laid out in the project's phase roadmap (Phase 0: refactor/rescope, Phase 1: backend foundation, and onward). The network foundation and OIDC-authenticated CI/CD bootstrap are intact and deployed; the application, data, and security-ops layers are being rebuilt from scratch on top of them.

## Current State

| Layer | Status |
|-------|--------|
| Network (VPC, subnets, IGW, NAT) | ✅ Deployed — see [Architecture](#architecture) |
| CI/CD (GitHub Actions OIDC, Terraform remote state) | ✅ Deployed — unchanged by the rescope |
| Compute, Data, Secrets, ACM/TLS | 🚧 Removed, being redesigned |
| Detection & response (CloudTrail, GuardDuty, Security Hub, automated remediation) | 🚧 Removed, logging/monitoring being redesigned |
| Container scanning (Trivy) | 🚧 Removed from CI until there's an image to scan again |

## Architecture

![Architecture Diagram](./docs/screenshots/architecture-diagram.png)

*Diagram reflects the original full-stack design — see [Current State](#current-state) above for what's actually deployed right now.*

### Components (current)

| Layer | Service | Purpose |
|-------|---------|---------|
| Networking | VPC, Public/Private Subnets (App + DB tiers, empty), NAT Gateway | Network isolation, reserved for compute and data in private subnets |
| CI/CD | GitHub Actions | OIDC auth (no stored credentials), security scanning, Terraform plan/apply |

## Security Controls

| Control | Implementation |
|---------|---------------|
| OIDC authentication | GitHub Actions authenticates via short-lived tokens exchanged through AWS STS — no stored AWS credentials |
| Least-privilege IAM | Scoped plan/deploy roles by GitHub event type, permissions boundary on the deploy role |
| Network isolation | Public/private subnet split across two AZs |
| Pipeline security | Gitleaks (secret scanning) and Checkov (IaC misconfiguration scanning) gate every PR |

More controls (secrets management, TLS, container scanning, audit logging, threat detection) return as the application and security-ops layers are rebuilt.

## Quick Start

### Prerequisites
- AWS CLI configured with appropriate credentials
- Terraform >= 1.0
- GNU Make

### Configuration
Project naming (used to prefix every AWS resource, the state bucket, and the IAM roles) is set once in `infrastructure/terraform/terraform.tfvars` — no code edit needed to rename or fork this project. `infrastructure/terraform/ci-oidc/terraform.tfvars` and `infrastructure/terraform/backend-state-init/terraform.tfvars` control the bootstrap layer the same way.

### Deploy
```bash
make deploy
```
Manual/break-glass path only — see the Makefile. The primary deploy path is the GitHub Actions "Deploy Infrastructure" workflow (OIDC-authenticated, no local credentials needed).

### Destroy
```bash
make destroy
```

## Known Limitations

- Single environment (dev) — multi-environment separation is out of scope for this project
- Cost-optimized for portfolio use — designed for full teardown/rebuild, not persistent uptime
- Application, data, and security-ops layers are mid-rebuild; see [Current State](#current-state)

## Tech Stack

| Tool | Version | Purpose |
|------|---------|---------|
| Terraform | >= 1.0 | Infrastructure as Code |
| GitHub Actions | - | CI/CD with OIDC authentication |
| Checkov | - | IaC security scanning |
| Gitleaks | - | Secret detection |

## Repository Structure

```
.
├── docs/                     # Security design, incident narratives, evidence (being revised)
├── infrastructure/
│   └── terraform/
│       ├── backend-state-init/   # Bootstrap for remote state (S3 + DynamoDB)
│       ├── ci-oidc/              # GitHub Actions OIDC federation
│       └── modules/
│           └── network/          # VPC, subnets, IGW, NAT — the only active module
├── .github/
│   └── workflows/
│       ├── pr-checks.yml         # Security scans + terraform plan on PRs
│       └── deploy.yml            # Terraform apply on merge/dispatch
├── Makefile                  # Deploy/destroy orchestration (break-glass fallback)
└── README.md
```

## Related Projects

This project builds on [Secure AWS Architecture Capstone](https://github.com/Zach-Maestas/secure-aws-architecture-capstone), which established the foundational VPC architecture and EC2-based deployment. This project evolved that baseline to ECS Fargate with secrets injection, and is now being extended with deeper backend engineering.

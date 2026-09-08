# 🛡️ AWS Security Findings Platform

A production-oriented cloud security findings and remediation platform: detects risky AWS activity, records and manages findings through a backend API, and performs reliable automated remediation. Combines backend software engineering (Python/FastAPI, PostgreSQL, Redis, Go workers) with infrastructure/platform engineering (AWS, Terraform, CI/CD, eventually Kubernetes/EKS).

Formerly "AWS Cloud Security Operations & DevSecOps Project" — renamed to match the direction laid out in the project's phase roadmap (Phase 0: refactor/rescope, Phase 1: backend foundation, and onward). The OIDC-authenticated CI/CD bootstrap and Terraform state backend are deployed; the network foundation is defined and pending its first apply. The application, data, and security-ops layers are being rebuilt from scratch on top of them.

## Current State

| Layer | Status |
|-------|--------|
| Network (VPC, subnets, IGW, NAT) | 🚧 Defined, pending first apply — see [Architecture](#architecture) |
| CI/CD (GitHub Actions OIDC, Terraform remote state) | ✅ Deployed — state locking migrated to S3 native lockfiles |
| Compute, Data, Secrets, ACM/TLS | 🚧 Removed, being redesigned |
| Detection & response (CloudTrail, GuardDuty, Security Hub, automated remediation) | 🚧 Removed, logging/monitoring being redesigned |
| Container scanning (Trivy) | 🚧 Removed from CI until there's an image to scan again |

## Architecture

A diagram of the full target architecture will return once the application and data
layers are rebuilt. See [Current State](#current-state) for what exists today, and
[docs/deployment.md](./docs/deployment.md) for how the pieces are provisioned.

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
| State protection | Versioned, encrypted state bucket; read/write/lock access split so PR-triggered roles cannot write state |

See [docs/security.md](./docs/security.md) for the threat model behind these, and for a tracked list of known gaps.

More controls (secrets management, TLS, container scanning, audit logging, threat detection) return as the application and security-ops layers are rebuilt.

## Quick Start

### Prerequisites
- AWS CLI configured with appropriate credentials
- Terraform >= 1.10.0 (required for S3 native state locking)
- GNU Make

### Configuration
Project naming (used to prefix every AWS resource, the state bucket, and the IAM roles) is set once in `infrastructure/terraform/terraform.tfvars` — no code edit needed to rename or fork this project. `infrastructure/terraform/ci-oidc/terraform.tfvars` and `infrastructure/terraform/bootstrap/terraform.tfvars` control the bootstrap layer the same way.

### Deploy
```bash
make deploy
```
Manual/break-glass path only — see the Makefile. The primary deploy path is the GitHub Actions "Deploy Infrastructure" workflow (OIDC-authenticated, no local credentials needed), dispatched from `main`.

First-time setup requires applying the bootstrap layers in order — see [docs/deployment.md](./docs/deployment.md).

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
| Terraform | >= 1.10.0 | Infrastructure as Code |
| GitHub Actions | - | CI/CD with OIDC authentication |
| Checkov | - | IaC security scanning |
| Gitleaks | - | Secret detection |

## Repository Structure

```
.
├── docs/
│   ├── deployment.md         # Provisioning order, deploy paths, troubleshooting
│   └── security.md           # Threat model, IAM design, known gaps
├── infrastructure/
│   └── terraform/            # Root config — the platform (remote state)
│       ├── bootstrap/        # S3 state bucket (local state)
│       ├── ci-oidc/          # GitHub OIDC provider + CI roles (local state)
│       └── modules/
│           └── network/      # VPC, subnets, IGW, NAT — the only active module
├── .github/
│   └── workflows/
│       ├── pr-checks.yml     # Security scans + terraform plan on PRs
│       └── deploy.yml        # Terraform apply via manual dispatch
├── Makefile                  # Deploy/destroy orchestration (break-glass fallback)
└── README.md
```

## Related Projects

This project builds on [Secure AWS Architecture Capstone](https://github.com/Zach-Maestas/secure-aws-architecture-capstone), which established the foundational VPC architecture and EC2-based deployment. That work was extended to ECS Fargate with secrets injection, which has since been torn out and is being rebuilt here with deeper backend engineering.

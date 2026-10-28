# 🛡️ AWS Security Findings Platform

A production-oriented cloud security findings and remediation platform: detects risky AWS activity, records and manages findings through a backend API, and performs reliable automated remediation. Combines backend software engineering (Python/FastAPI, PostgreSQL, SQS) with infrastructure/platform engineering (AWS, Terraform, ECS Fargate, CI/CD).

The OIDC-authenticated CI/CD pipeline and Terraform state backend are deployed, and the network foundation is defined and pending its first apply. The findings API is being built next. See the [Roadmap](#roadmap).

## Current State

| Layer | Status |
|-------|--------|
| CI/CD (GitHub Actions OIDC, Terraform remote state) | ✅ Deployed — S3 native state locking |
| Network (VPC, subnets, IGW, NAT) | 🚧 Defined, pending first apply |
| Findings API (FastAPI, PostgreSQL) | 🚧 Phase 1 — in progress |
| Compute, data, secrets (ECS, RDS, Secrets Manager) | Planned — Phase 2 |
| Detection & remediation (CloudTrail, EventBridge, SQS) | Planned — Phase 2 |
| Container scanning (Trivy) | Planned — Phase 1, once there is an image to scan |

## Roadmap

| Phase | Focus | Status |
|---|---|---|
| 0 | Baseline: fixtures, data model decisions, docs cleanup | ✅ Done |
| 1 | Backend + tests: FastAPI, PostgreSQL, dedup, CI test gates | 🚧 In progress |
| 2 | End-to-end MVP: ECS + RDS, EventBridge → SQS ingest, remediation, auth, audit trail | Planned |

Scope, "done" criteria, and what is deliberately out of scope: [docs/roadmap.md](./docs/roadmap.md).

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
First-time setup applies the bootstrap layers in order — see [docs/deployment.md](./docs/deployment.md).

After that, infrastructure is deployed by the GitHub Actions **Deploy Infrastructure** workflow, dispatched from `main`. It authenticates through OIDC, so no AWS credentials are stored or needed locally.

### Break-glass (local)
```bash
make deploy
make destroy
```
These run with your own credentials and are only for when Actions is unavailable — see the Makefile.

### Run the API locally
See [application/README.md](./application/README.md).

## Known Limitations

- Single environment (dev) — multi-environment separation is out of scope for this project
- Cost-optimized for portfolio use — designed for full teardown/rebuild, not persistent uptime
- Application, data, and detection layers are being built in phases; see the [Roadmap](#roadmap)

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
├── application/              # FastAPI findings service (Python, uv)
│   └── src/findings_platform/
├── docs/
│   ├── roadmap.md            # Phases and done criteria
│   ├── data-model.md         # Schema, lifecycle, deduplication
│   ├── api.md                # REST conventions and endpoints
│   ├── security.md           # Threat model, IAM design, known gaps
│   └── deployment.md         # Provisioning order, deploy paths, troubleshooting
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

This project builds on [Secure AWS Architecture Capstone](https://github.com/Zach-Maestas/secure-aws-architecture-capstone), which established the foundational VPC architecture, an ECS Fargate deployment with secrets injection, and automated remediation pipelines. That work is being rebuilt here around a backend findings service.

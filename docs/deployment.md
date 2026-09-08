# Deployment Guide

How this project's infrastructure is provisioned, in what order, and why that order exists.
For a summary of what currently exists, see the [README](../README.md#current-state).

---

## Architecture

The Terraform lives in three independent configurations, each with its own state.
They are not modules of one another — each is applied separately.

| Configuration | State | Provisions |
|---|---|---|
| `infrastructure/terraform/bootstrap/` | Local | S3 bucket holding remote state |
| `infrastructure/terraform/ci-oidc/` | Local | GitHub OIDC provider, plan/deploy roles, IAM policies, permissions boundary |
| `infrastructure/terraform/` (root) | S3 remote | The platform itself — currently the network module |

### Why two configurations use local state

The root configuration stores its state in an S3 bucket. That bucket has to exist
before the backend can be initialized, so it cannot be created by the configuration
that depends on it. `bootstrap/` breaks that cycle by running against local state.

`ci-oidc/` stays local for a related reason: it creates the IAM roles that CI assumes.
If it used the remote backend, the roles would need permission to manage themselves,
and recovering from a broken policy would require the very credentials the broken
policy had just revoked. Local state keeps it recoverable with your own credentials.

Neither is applied often. Both are applied by a human, deliberately.

---

## Prerequisites

| Tool | Version | Verify |
|---|---|---|
| AWS CLI | v2 | `aws --version` |
| Terraform | >= 1.10.0 | `terraform version` |
| GNU Make | any | `make --version` |

Terraform 1.10 is a hard floor: the S3 backend uses native lockfile locking
(`use_lockfile`), which does not exist in earlier versions.

Your local IAM identity needs enough access to create the state bucket and the
CI IAM roles. That is a deliberate exception to this project's no-stored-credentials
posture — see [security.md](./security.md).

---

## First-Time Setup

Applied in this order, once:

### 1. `bootstrap/` — state backend

```bash
cd infrastructure/terraform/bootstrap
terraform init
terraform apply
```

Creates the state bucket with versioning, AES256 encryption, public access blocked,
and SSE-C uploads rejected.

### 2. `ci-oidc/` — CI identity

```bash
cd infrastructure/terraform/ci-oidc
terraform init
terraform apply
```

Creates the OIDC provider, the `plan` and `deploy` roles, their policies, and the
permissions boundary. `bootstrap/` and `ci-oidc/` have no dependency on each other
and can be applied in either order — both must precede the root configuration.

### 3. Root — the platform

```bash
cd infrastructure/terraform
terraform init
terraform plan
```

Do not apply this locally unless you are breaking glass. See below.

---

## Deploying Changes

### Primary path — GitHub Actions

Infrastructure changes are applied by the **Deploy Infrastructure** workflow,
triggered manually via `workflow_dispatch`. The job authenticates through OIDC
and assumes the deploy role; no AWS credentials are stored in GitHub.

**Dispatch from `main`.** The deploy role's trust policy requires a subject claim of
`...:ref:refs/heads/main`. Dispatching from a feature branch produces a different
claim and fails at the assume-role step, before Terraform runs.

Opening a PR against `main` runs the plan path instead: format check, validate,
secret scan, IaC scan, then `terraform plan` under the read-only plan role.

### Break-glass path — local

```bash
make deploy    # init + apply + fmt
make destroy
```

These run as *you*, with your own credentials — not as the deploy role. They are for
when Actions is unavailable. Note that a successful local apply proves nothing about
the CI role's permissions, since it never exercises them.

---

## Verification

After an apply:

```bash
terraform output          # vpc_id and the three subnet ID lists
terraform plan            # should report no changes
```

Confirm the lock behaved correctly — during an apply, `platform/terraform.tfstate.tflock`
exists in the state bucket; afterwards it is gone. A leftover `.tflock` means the
unlock failed, usually a missing `s3:DeleteObject`.

---

## State

| Property | Value |
|---|---|
| Bucket | `aws-security-findings-platform-tfstate` |
| Key | `platform/terraform.tfstate` |
| Locking | S3 native (`use_lockfile`), conditional writes |
| Versioning | Enabled — a bad write is recoverable |

The key is namespaced by component (`platform/`), not by environment. This project has
a single environment by design; future configurations get sibling keys.

The key appears in both `backend.tf` and `ci-oidc/variables.tf` (as `tfstate_key`, used
to scope the IAM policy). Backend blocks cannot use variables, so nothing enforces that
they match — a mismatch surfaces as an access denial on the next apply.

---

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `Backend configuration changed` | Cached backend config in `.terraform/` disagrees with `backend.tf` | `terraform init -reconfigure`, or delete `.terraform/` |
| `locked provider ... does not match configured version constraints` | `.terraform.lock.hcl` and `required_providers` disagree | `terraform init -upgrade`, commit the lock file |
| Assume-role fails on dispatch | Dispatched from a branch other than `main` | Merge first, dispatch from `main` |
| `AccessDenied` mid-apply | Deploy policy is missing an action | Read the action name from the error, add it to `ci-oidc/main.tf`, re-apply `ci-oidc/` |
| Apply blocks on an existing lock | A previous run failed to release it | Confirm no run is active, then `terraform force-unlock <id>` |

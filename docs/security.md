# Security Design

The security posture of this project's infrastructure and delivery pipeline: what it
defends against, how, and what it does not yet cover.

---

## Threat Model

The infrastructure has no users and no public endpoints right now, so the meaningful
attack surface is the **delivery pipeline** — the path from a commit to AWS API calls.

Threats considered:

| Threat | Concern |
|---|---|
| Malicious or compromised pull request | PR-triggered CI runs code from an untrusted branch, with AWS access |
| Compromised third-party GitHub Action | Actions run in-process and can reach any credential the job holds |
| Leaked long-lived AWS credentials | A static access key in CI is stealable and rarely rotated |
| Privilege escalation from CI | A deploy role that can create IAM roles can create a more powerful one |
| State file tampering or loss | Terraform state is the source of truth; corrupting it is as damaging as deleting resources |

Explicitly out of scope for now: application security, data protection, and runtime
threat detection. Those return with the application and security-ops layers.

---

## Identity and Access

### GitHub Actions to AWS

Authentication uses OIDC federation. GitHub mints a short-lived token, AWS STS exchanges
it for temporary credentials. No AWS access keys are stored in GitHub.

The trust policy pins the subject claim using GitHub's **immutable numeric IDs** rather
than names:

```
repo:OWNER@<owner_id>/REPO@<repo_id>:<context>
```

Repository and organization names can be changed or transferred; the numeric IDs cannot.
Matching on names alone means a renamed or transferred repository could satisfy a trust
policy it should no longer satisfy.

### Two roles, split by trust level

| Role | Assumable when | Permissions |
|---|---|---|
| `...-github-actions-plan` | Subject ends `:pull_request` | Read-only: `ec2:Describe*`, read state, take the state lock |
| `...-github-actions-deploy` | Subject ends `:ref:refs/heads/main` | Provisioning: network writes, write state |

A pull request can come from an untrusted branch, so the plan role is the weaker of the
two by design. The deploy role is reachable only from `main`, which is protected by
review.

### Permissions boundary

The deploy role carries a permissions boundary. Its purpose is not to constrain the role
directly — the identity policy is already narrower — but to constrain any role the deploy
role *creates*. Without it, a role with `iam:CreateRole` could create an administrator
role and pass to it, escaping its own limits. The boundary denies creating roles that do
not themselves carry the boundary, along with a set of account-level escalation actions.

**Current status:** inert. The deploy role has no IAM permissions at all right now, so
nothing the boundary denies is reachable. It becomes load-bearing when a module needs
IAM roles — ECS task roles, Lambda execution roles.

---

## Least Privilege

The deploy role is scoped to what is actually deployed, not to what might be deployed
later. Today that is the network module: `ec2:Describe*` plus create/modify/delete on
VPCs, subnets, route tables, gateways, EIPs and NAT gateways.

Each future module ships with its matching IAM change in the same pull request. The cost
is that a missing permission surfaces as a mid-apply `AccessDenied`; the benefit is that
the role's permissions describe the system rather than a wishlist.

`ec2:Describe*` is granted on `Resource: "*"`. This is required, not a shortcut — EC2
Describe actions do not support resource-level permissions in IAM.

---

## Terraform State Protection

The state bucket blocks public access, enforces AES256 at rest, keeps versioning enabled,
and rejects SSE-C uploads. SSE-C lets a caller supply their own encryption key; an
attacker with write access could re-upload state under a key we do not hold, making it
unreadable. Versioning means a bad or malicious write is recoverable.

Access is split into three grants rather than one:

| Grant | Resource | Held by |
|---|---|---|
| Read state | `platform/terraform.tfstate` | Plan and deploy |
| Acquire/release lock | `platform/terraform.tfstate.tflock` | Plan and deploy |
| Write state | `platform/terraform.tfstate` | Deploy only |

`terraform plan` reads state and takes a lock but never writes state, so the plan role has
no reason to hold write access — and giving it none means a pull request cannot corrupt or
delete state. Both grants name exact object keys rather than `bucket/*`, so neither role
can reach state belonging to another configuration.

Locking uses S3 conditional writes rather than a DynamoDB table, removing a resource and
an IAM grant from the system.

---

## Pipeline Controls

Every pull request against `main` must pass, before `terraform plan` runs:

| Check | Tool |
|---|---|
| Formatting and syntax | `terraform fmt -check`, `terraform validate` |
| Secret detection | Gitleaks, full history |
| IaC misconfiguration | Checkov |

`GITHUB_TOKEN` permissions default to `contents: read` at workflow level. Only the plan
job is granted `id-token: write`. The scanning jobs run third-party actions, and any code
in a job holding that permission can mint an OIDC token and assume the plan role — so the
jobs that never talk to AWS are not given the ability to.

---

## Known Gaps

Tracked deliberately rather than left implicit.

| Gap | Impact | Planned |
|---|---|---|
| Network write actions use `Resource: "*"` | The deploy role can delete VPCs it did not create | Tag conditions via `aws:RequestTag` / `aws:ResourceTag`, once resources carry the `Project` tag |
| `ec2:CreateTags` unconstrained | A role that can tag anything can tag past its own tag conditions | Constrain with `ec2:CreateAction` alongside the tag conditions |
| GitHub Actions pinned to mutable tags | A compromised tag changes what runs in the pipeline | Pin to commit SHAs |
| No CloudTrail trail | Only 90-day Event history; no data events, no IAM Access Analyzer policy generation | Returns with the security-ops layer |
| Local break-glass path uses admin credentials | Bypasses the OIDC posture the pipeline enforces | Accepted; documented in the Makefile |
| Permissions boundary currently inert | No active defense today | Resolves when IAM-creating modules land |

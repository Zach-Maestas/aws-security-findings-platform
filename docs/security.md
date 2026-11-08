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
| Compromised third-party GitHub Action | Actions run in-process and can reach any credential the job holds. This happened to `trivy-action` in 2026; see [Supply Chain](#supply-chain) |
| Leaked long-lived AWS credentials | A static access key in CI is stealable and rarely rotated |
| Privilege escalation from CI | A deploy role that can create IAM roles can create a more powerful one |
| State file tampering or loss | Terraform state is the source of truth; corrupting it is as damaging as deleting resources |

Explicitly out of scope for now: application security, data protection, and runtime
threat detection. Those arrive with the deployed application in Phase 2.

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

Every pull request against `main` runs the checks below. A branch ruleset on `main`
requires them, so a failing check blocks the merge. `terraform plan` runs only after the
Terraform checks pass.

| Check | Tool |
|---|---|
| Formatting and syntax | `terraform fmt -check`, `terraform validate` |
| Secret detection | Gitleaks, full history |
| IaC misconfiguration | Checkov |
| Application tests | pytest, unit and integration, against a Postgres service container |
| Application lint | Ruff: `ruff check`, `ruff format --check` |
| Container vulnerabilities | Trivy: fixable CRITICAL and HIGH fail the build |

`GITHUB_TOKEN` permissions default to `contents: read` at workflow level. Only the plan
job is granted `id-token: write`. The scanning jobs run third-party actions, and any code
in a job holding that permission can mint an OIDC token and assume the plan role — so the
jobs that never talk to AWS are not given the ability to.

---

## Application Security

Already in place:

- **Input validation.** Request bodies are validated against Pydantic schemas before any
  application code runs; invalid input returns `422` without echoing the submitted value.
- **No internal details in errors.** Unexpected errors return a generic `500`; the
  traceback goes to the server logs only. See [api.md](./api.md#errors).

Added in Phase 2 alongside the deployed API: API-key authentication with two roles, a
status-history audit trail, database credentials in Secrets Manager, and remediation. See
[roadmap.md](./roadmap.md).

---

## Known Gaps

Tracked deliberately rather than left implicit.

| Gap | Impact | Planned |
|---|---|---|
| Network write actions use `Resource: "*"` | The deploy role can delete VPCs it did not create | Tag conditions via `aws:RequestTag` / `aws:ResourceTag`, once resources carry the `Project` tag |
| `ec2:CreateTags` unconstrained | A role that can tag anything can tag past its own tag conditions | Constrain with `ec2:CreateAction` alongside the tag conditions |
| Most GitHub Actions pinned to mutable tags | A compromised tag changes what runs in the pipeline (`trivy-action` is already SHA-pinned) | Pin the rest to commit SHAs, with Dependabot proposing updates |
| No CloudTrail trail | Only 90-day Event history; no data events, no IAM Access Analyzer policy generation | Phase 2 — the detection pipeline (EventBridge → SQS) depends on it |
| Local break-glass path uses admin credentials | Bypasses the OIDC posture the pipeline enforces | Accepted; documented in the Makefile |
| Permissions boundary currently inert | No active defense today | Resolves when IAM-creating modules land |

---

## Human Access

People sign in through **AWS IAM Identity Center**, not IAM users:

- **No long-lived credentials.** Each sign-in produces a short-lived role session that
  expires; there are no static access keys to leak.
- **MFA at sign-in.** Identity Center enforces MFA before any role session is issued.
  (CloudTrail's `sessionContext.attributes.mfaAuthenticated` reads `false` for these
  sessions, because it only reports IAM's own MFA check; MFA happened at the Identity
  Center sign-in.)
- **Access through a group.** The `AdministratorAccess` permission set is assigned to the
  `Admins` group, not to individual users, so access is granted and revoked in one place.
- **Attributable.** CloudTrail records the role and the person: the session name at the
  end of `assumed-role/AWSReservedSSO_AdministratorAccess_.../<user>`.

Human access is configured manually as an account baseline, outside this project's
Terraform. Managing it from the project's pipeline would mean granting the deploy role
Organizations and SSO-admin permissions, which is the opposite of least privilege. CI uses
its own OIDC roles (see above). Setup and CLI use are in
[deployment.md](./deployment.md#human-access).

**Accepted limitation:** the single AWS account is also the Organizations management
account. In a company, workloads would run in separate member accounts.

---

## Supply Chain

- **Actions pinned by commit SHA.** A version tag is a movable pointer: anyone with write
  access to an action's repository, or an attacker with stolen access, can move it to
  different code, and every workflow using the tag runs it. In March 2026,
  `aquasecurity/trivy-action` had 76 of its 77 tags force-pushed to credential-stealing
  code (CVE-2026-33634). This project's container scan pins `trivy-action` to a commit
  SHA, with the version in a comment. Pinning the remaining actions is a known gap below.
- **Container scanning.** Every PR builds the image and fails on fixable CRITICAL or HIGH
  vulnerabilities.
- **Unused tools removed, not suppressed.** Trivy flagged HIGH CVEs in libraries bundled
  inside pip. The application never runs pip (uv installs dependencies), so pip is
  uninstalled from the runtime image rather than ignoring the findings.
- **Non-root container.** The API runs as an unprivileged `appuser`.

---

## Defense in Depth

Detection is the safety net, not the first line:

| Layer | Goal | In this project |
|---|---|---|
| **Prevent** | Stop risky changes from happening | Least-privilege CI roles, permissions boundary, Checkov before deploy, short-lived human sessions; region-restricting SCP (Phase 2) |
| **Detect** | Notice what gets through | CloudTrail-based detections for logging stopped, admin access granted, and security groups opened to the internet |
| **Respond** | Limit the damage quickly | Automatic remediation and alerting (Phase 2) |

Detection and response take minutes; prevention means most risky changes are never
possible at all.

---

## Known Detection Limitations

| Limitation | Impact | Planned |
|---|---|---|
| EventBridge rules are regional | A security group opened in a region without a rule is not detected | Phase 2: an SCP restricting the account to the regions in use; forward events from any other allowed region |
| `ModifySecurityGroupRules` does not say whether a rule is inbound or outbound | An outbound rule edited to an open range is reported as a finding | Phase 2: look the rule up with `DescribeSecurityGroupRules` in the consumer |
| `UpdateAssumeRolePolicy` is not detected | A role's trust policy can be changed to let an outside account assume it | Future: needs a new detection type and trust-policy analysis |
| Failed attempts are ignored | A burst of `AccessDenied` from one identity, a sign of a probed credential, is not reported | Future: behavioral detection over a time window |
| Prefix-list sources are skipped | A rule whose source is a prefix list containing `0.0.0.0/0` is not reported, because the event names the list but not its CIDRs. Editing the list later (`ModifyManagedPrefixList`) also opens every rule that uses it, with no security group event | Future: resolve the list with `GetManagedPrefixListEntries`, and detect prefix-list changes |
| A single-IP rule is treated as safe | An attacker with security group permissions can open SSH to their own `/32` without a finding | Prevention: security group changes only through Terraform, and SSM Session Manager instead of SSH. Future: an allowlist of approved CIDRs |

# Roadmap

Each phase ends with something that can be demonstrated. Detailed design decisions live
in the doc for the area being built, written as each part is built.

| Phase | Focus | Status |
|---|---|---|
| 0 | Baseline | ✅ Done |
| 1 | Backend + tests | 🚧 In progress |
| 2 | End-to-end MVP on AWS | Planned |

The project is complete after Phase 2. From then on, only bug fixes.

---

## Phase 0: Baseline

- Archive the predecessor project so its code stays visible (tag `v1-cloud-security`)
- Pare the docs back to what exists or is being built now
- Decide the Step 0 inputs: real CloudTrail fixtures (three detections plus one benign
  event), fingerprint fields, enum values, and recurrence handling — recorded in
  [data-model.md](./data-model.md)
- Tag `phase-0-baseline`

**Done when:** the tag exists and the Step 0 decisions are written down.

## Phase 1: Backend + Tests

- FastAPI, PostgreSQL, SQLAlchemy, Alembic, and docker-compose for local development
- Ingest endpoint that parses CloudTrail events into deduplicated findings; a repeat
  updates `last_seen_at` instead of creating a new row, and a duplicate event is
  skipped, so ingest is idempotent
- Findings endpoints with status changes, `/health` and `/ready`, structured JSON logs
- Tests in the same PRs as the code: pytest unit tests, integration tests against a
  Postgres service container, Ruff, and Trivy, all enforced in `pr-checks.yml`
- [api.md](./api.md) filled in as the endpoints are designed

**Done when:** a fixture POST creates a finding, a repeat collapses onto it, a duplicate
is skipped, and a broken change fails the PR.

## Phase 2: End-to-End MVP

- ECS Fargate and RDS deployed through GitHub Actions, using layered Terraform stacks
  (network → data → app), with the deploy role's IAM expanded in the same PRs
- One NAT gateway, a destroy workflow, and an AWS Budgets alert
- EventBridge → SNS → SQS (with a DLQ) → consumer, as the single path for every event.
  SNS fans out to two subscribers: the SQS queue for processing, and an email
  subscription that alerts on each detection. The consumer records the finding, then
  runs the capstone's remediation for that detection and records the result on the
  finding. A duplicate message must not create a duplicate finding or remediate twice
- Correlation IDs carried from the API through SQS to the consumer, so one event can be
  traced end to end in the logs
- API-key auth with two roles, a status-history table for the audit trail, and
  database credentials in Secrets Manager

**Done when:** the 60-second demo works (risky change → finding → remediation → audit
trail), and the README has an architecture diagram, a demo GIF, design decisions, and
a cost note.

---

## Out of scope

Left out on purpose, because this workload doesn't need them:

- **Caching (Redis):** the findings volume is small enough for Postgres alone
- **Kubernetes (kind, EKS):** ECS Fargate runs two services without a cluster to manage
- **Prometheus and Grafana:** structured logs and correlation IDs cover tracing at this
  scale

These are planned for a separate, smaller project built around a problem that needs
them.

# Roadmap

Each phase ends with something that can be demonstrated. Detailed design decisions live
in the doc for the area being built, written as each part is built.

| Phase | Focus | Status |
|---|---|---|
| 0 | Baseline | ✅ Done |
| 1 | Backend + tests | Planned |
| 2 | End-to-end MVP on AWS | Planned |
| 3 | Kubernetes + observability | Planned |

---

## Phase 0: Baseline

- Archive the predecessor capstone so its code stays visible
- Pare the docs back to what exists or is being built now
- Decide the Step 0 inputs: real CloudTrail fixtures (three detections plus one benign
  event), fingerprint fields, enum values, and recurrence handling — recorded in
  [data-model.md](./data-model.md)
- Tag `v0.1-baseline`

**Done when:** the tag exists and the Step 0 decisions are written down.

## Phase 1: Backend + Tests

- FastAPI, PostgreSQL, SQLAlchemy, Alembic, and docker-compose for local development
- Ingest endpoint that parses CloudTrail events into deduplicated findings; a repeat
  updates `last_seen_at` instead of creating a new row
- Findings endpoints with status changes, `/health` and `/ready`, structured JSON logs
- Tests in the same PRs as the code: pytest unit tests, integration tests against a
  Postgres service container, Ruff, and Trivy, all enforced in `pr-checks.yml`
- Redis cache-aside for the findings summary, with TTLs, invalidation on status change,
  and correct behavior when Redis is down

**Done when:** a fixture POST creates a finding, a repeat collapses onto it, a broken
change fails the PR, and the API keeps working with Redis stopped.

## Phase 2: End-to-End MVP

- ECS Fargate and RDS deployed through GitHub Actions, using layered Terraform stacks
  (network → data → app), with the deploy role's IAM expanded in the same PRs
- One NAT gateway, a destroy workflow, and an AWS Budgets alert
- EventBridge → SQS (with a DLQ) → consumer that records the finding; a duplicate
  message must not create a duplicate finding or remediate twice
- Re-integrate the capstone's Lambda remediation for the three detections, with its
  result recorded on the finding; how it is triggered (fan-out from EventBridge or
  chained after the finding is recorded) is a design decision for architecture.md
- API-key auth with two roles, a status-history table for the audit trail, and
  database credentials in Secrets Manager

**Done when:** the 60-second demo works (risky change → finding → remediation → audit
trail), and the README has an architecture diagram, a demo GIF, design decisions, and
a cost note.

## Phase 3: Kubernetes + Observability

- kind first: manifests, probes, resource limits, config and secrets; kind in CI to
  validate the manifests
- EKS via Terraform, with the permissions boundary constraining the node and pod roles
  the deploy role creates; RDS stays outside the cluster, and the cluster is torn down
  between sessions
- Prometheus and Grafana, correlation IDs carried from the API through SQS to the
  consumer, and actionable alarms with short runbooks

**Done when:** the app runs on EKS, the dashboard shows real metrics, and the README
documents the Kubernetes setup.

---

## Later (optional)

- A Go CLI client for the API

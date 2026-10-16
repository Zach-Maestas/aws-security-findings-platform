# Data Model

<!-- What the database stores and the rules it enforces. The ER diagram is the
     source of truth for shape; this doc explains the why. -->

---

## ER Diagram
```mermaid
erDiagram
    FINDING ||--o{ EVENT : "has"
    FINDING {
        int id PK
        enum detection_type
        enum severity
        enum status
        text fingerprint
        text account
        text region
        text resource
        enum suppression_reason
        timestamptz created_at
        timestamptz updated_at
        timestamptz last_seen_at
        timestamptz resolved_at
    }
    EVENT {
        int id PK
        int finding_id FK
        text cloudtrail_event_id UK
        text event_name
        timestamptz event_time
        text actor
        text source_ip
        jsonb raw_event
    }
```

---

## Entities

<!-- For each entity: what one row represents, who creates it, and when it changes. -->

### Finding
**What one row represents**: one problem, as defined by its fingerprint.
**What creates it**: ingest, when a risky event arrives with no matchable finding for its fingerprint. The finding and its first event are inserted in one transaction.
**When it changes**: `last_seen_at` when a new event matches; `status` (with `updated_at` and `resolved_at`) through lifecycle transitions; `severity` can rise when a matching event is more severe; remediation results arrive in Phase 2.
**What `resource` holds**: the normalized ARN of the affected resource. For AdminAccess this is the principal ARN, since the principal is what remediation acts on.
**What `account` and `region` hold**: copies of values in the `resource` ARN, kept as columns for filtering. `region` is NULL for IAM findings, since IAM resources are global.

### Event
**What one row represents**: one occurrence, a single CloudTrail record linked to the finding it caused.
**What creates it**: ingest, for every risky event that passes the duplicate check.
**When it changes**: never. Events are an immutable record.
**Benign events**: only events that produce or match a finding are stored; benign events are dropped. CloudTrail is the system of record for all API activity. As a result, `finding_id` is NOT NULL.

---

## Enumerations

<!-- Allowed values and what each one means. -->

| Enum | Values | Notes |
|---|---|---|
| `detection_type` | `CLOUDTRAIL_LOGGING_STOPPED`, `ADMIN_ACCESS_GRANTED`, `SG_OPEN_TO_WORLD` | One value per detection rule; also the fingerprint prefix. |
| `severity` | `LOW`, `MEDIUM`, `HIGH`, `CRITICAL` | `CLOUDTRAIL_LOGGING_STOPPED` = HIGH. `ADMIN_ACCESS_GRANTED` = CRITICAL. `SG_OPEN_TO_WORLD` depends on the worst world-open rule: all traffic (`-1`) = CRITICAL; a range including 22 or 3389 = HIGH; any other port = MEDIUM. Severity only rises: a matching event sets it to the higher of the two. `LOW` is reserved for future detections. |
| `status` | `OPEN`, `RESOLVED`, `SUPPRESSED` | `OPEN` and `SUPPRESSED` are **matchable**: new events with the same fingerprint attach to them. `RESOLVED` is final. |
| `suppression_reason` | `ACCEPTED_RISK`, `FALSE_POSITIVE`, `INTENDED` | Required when `status` is `SUPPRESSED`, NULL otherwise. |

---

## Finding Lifecycle

```mermaid
stateDiagram-v2
    [*] --> OPEN : ingest (first risky event, no matchable finding)
    OPEN --> OPEN : ingest (matching event, last_seen_at updated)
    OPEN --> RESOLVED : user marks resolved (Phase 2 - or remediation succeeds)
    OPEN --> SUPPRESSED : user suppresses (reason required)
    SUPPRESSED --> SUPPRESSED : ingest (matching event, stays suppressed)
    SUPPRESSED --> OPEN : user unsuppresses (reason cleared)
    RESOLVED --> [*]
```

| Transition | Trigger | Rule |
|---|---|---|
| → `OPEN` | Ingest | First risky event with no matchable finding for its fingerprint |
| `OPEN` → `RESOLVED` | User (Phase 2: remediation) | Sets `resolved_at` |
| `OPEN` → `SUPPRESSED` | User | `suppression_reason` required |
| `SUPPRESSED` → `OPEN` | User | Clears `suppression_reason` |
| Anything else | — | Rejected by the API (409) |

### Recurrence

- **Matches a `SUPPRESSED` finding:** the event attaches and the finding stays suppressed. Suppression means "known and accepted," so repeats don't re-alert.
- **Matches only a `RESOLVED` finding:** a **new** `OPEN` finding is created. The resolved finding stays as a closed historical record, which keeps time-to-resolve accurate; the problem coming back is treated as a new incident.

Transition details (who, when, notes) are recorded by the status-history table in Phase 2.

---

## Deduplication and Fingerprinting

<!-- How `fingerprint` is computed, why repeated events collapse onto one finding,
     and how `last_seen_at` / `cloudtrail_event_id` uniqueness support that. -->

### Normalization

Every identifier in a fingerprint is converted to its full ARN, so the same resource
always produces the same fingerprint.

| Component | Source field | Rule |
|---|---|---|
| Trail ARN | `requestParameters.name` | Already an ARN → keep it. Bare name → `arn:aws:cloudtrail:{awsRegion}:{recipientAccountId}:trail/{name}` |
| Principal ARN | `requestParameters.roleName` / `userName` / `groupName` | Always built: `arn:aws:iam::{recipientAccountId}:{role\|user\|group}/{name}` |
| Policy ARN | `requestParameters.policyArn` | Always an ARN → keep it |
| Security group ARN | `requestParameters.groupId` | Always built: `arn:aws:ec2:{awsRegion}:{recipientAccountId}:security-group/{groupId}` |

IAM is a global service, so IAM ARNs have no region — the slot between `iam::` is
intentionally empty.

### Detections --> Fingerprints

| Detection | Fingerprint |
|---|---|
| CloudTrail logging stopped | `CLOUDTRAIL_LOGGING_STOPPED\|arn:aws:cloudtrail:us-east-1:111122223333:trail/test-stop-logging-trail` |
| AdministratorAccess attached | `ADMIN_ACCESS_GRANTED\|arn:aws:iam::111122223333:role/test-iam-attach-admin-role\|arn:aws:iam::aws:policy/AdministratorAccess` |
| SG open to the world | `SG_OPEN_TO_WORLD\|arn:aws:ec2:us-east-1:111122223333:security-group/sg-0123456789abcdef0` | 

- **Format:** components joined with `|`, no spaces, stored as plain text (not hashed): short, structured, and readable when debugging.
- **Excluded:** everything under `userIdentity`, plus `eventID`, `eventTime`, `sourceIPAddress`, `userAgent`, and `eventName`. These describe the occurrence, not the problem, and are stored on the EVENT row.
- **Trail**: Includes the trail arn itself to differentiate between different trails.
- **IAM**: One finding per principal and policy, because remediation detaches one policy from one principal.
- **SG**: One finding per security group. This keeps EVENT→FINDING many-to-one; per-rule findings would need a linking table (deferred).

---


## Constraints and Indexes

| Table | Constraint / Index | Purpose |
|---|---|---|
| `finding` | PK `id` | Row identity |
| `finding` | NOT NULL on `detection_type`, `severity`, `status`, `fingerprint`, `account`, `resource`, `created_at`, `updated_at`, `last_seen_at` | Every finding is fully identified |
| `finding` | Partial UNIQUE on `fingerprint` WHERE `status IN ('OPEN', 'SUPPRESSED')` | At most one matchable finding per problem, even under concurrent ingest; also serves the ingest lookup |
| `finding` | CHECK `(status = 'SUPPRESSED') = (suppression_reason IS NOT NULL)` | Reason present exactly when suppressed |
| `finding` | CHECK `(status = 'RESOLVED') = (resolved_at IS NOT NULL)` | `resolved_at` present exactly when resolved |
| `finding` | CHECK `(detection_type = 'ADMIN_ACCESS_GRANTED') = (region IS NULL)` | IAM findings have no region; all others must |
| `event` | PK `id` | Row identity |
| `event` | UNIQUE `cloudtrail_event_id` | Rejects duplicate delivery of the same CloudTrail event |
| `event` | FK `finding_id` → `finding.id`, NOT NULL | Every stored event belongs to a finding |
| `event` | Index on `finding_id` | Loading a finding's events (Postgres does not index foreign keys automatically) |

Indexes for list filtering (status, severity, `last_seen_at`) are added in 1.6, once the queries exist.

---

## Migrations

<!-- Alembic workflow: how to generate, review, and apply a migration,
     and the rules for changes that aren't backwards compatible. -->

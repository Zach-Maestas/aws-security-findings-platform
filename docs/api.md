# API Reference

The contract the backend exposes. FastAPI serves interactive docs at `/docs`; this file
covers the conventions and reasoning the generated schema can't show.

---

## Conventions

- **Base path:** business endpoints are served under `/api/v1`. `/health` and `/ready`
  are unversioned, at the root, so load balancers and orchestrators can reach them without
  knowing the API version.
- **Versioning:** a breaking change to a request or response shape goes into a new
  version (`/api/v2`) while `v1` keeps its contract.
- **Content type:** JSON in, JSON out.
- **Naming:** `snake_case` field names in requests and responses. CloudTrail's own
  camelCase field names are accepted as-is in ingest bodies.
- **Timestamps:** UTC, ISO 8601 (`2026-11-01T17:55:15Z`).
- **Schemas:** every request body and response is a Pydantic model in `schemas/`, so it is
  validated on the way in and documented in `/docs`.

---

## Authentication and Authorization

None in Phase 1; the API runs locally only. Phase 2 adds API keys with two roles, a
read-only role and a responder role that can change finding status, and records which
key made each change. See [security.md](./security.md#application-security).

---

## Endpoints

### Health

| Method | Path | Purpose | Success | Failure |
|---|---|---|---|---|
| `GET` | `/health` | The process is up. Touches nothing else | `200 {"status": "ok"}` | n/a |
| `GET` | `/ready` | The database is reachable (`SELECT 1`) | `200 {"status": "ready"}` | `503 service_unavailable` |

### Events

| Method | Path | Purpose | Success | Failure |
|---|---|---|---|---|
| `POST` | `/api/v1/events` | Ingest one CloudTrail record | `201` created, `200` otherwise | `422 invalid_event`, `422 validation_error` |

The body is **one CloudTrail record** (an element of a log file's `Records` array), sent
as-is in CloudTrail's camelCase. The response reports what happened to it:

```json
{
  "outcome": "created",
  "finding_id": "8aa9b55c-4696-4dd1-bb7f-a9f820f6d515",
  "reason": null
}
```

| `outcome` | Status | Meaning | `finding_id` | `reason` |
|---|---|---|---|---|
| `created` | 201 | A new OPEN finding was opened for this event | the new finding | `null` |
| `updated` | 200 | The event attached to an existing OPEN or SUPPRESSED finding with the same fingerprint | the existing finding | `null` |
| `duplicate` | 200 | An event with this `eventID` is already stored; nothing changed | `null` | `null` |
| `ignored` | 200 | No detection applies; nothing was stored | `null` | why (below) |

| `reason` | When |
|---|---|
| `error_code` | The call failed in AWS (the record has an `errorCode`, e.g. `AccessDenied`), so nothing changed |
| `unhandled_event_name` | No detection handles this `eventName` |
| `not_risky` | A detection handles it, but this change isn't risky (e.g. an SG rule open to one IP) |

**Ingest is idempotent.** Sending the same record any number of times leaves the same
state as sending it once, so retries are always safe:

- **Duplicate:** the `eventID` is unique across stored events, so a resend is skipped.
- **Repeat:** a new event with the same fingerprint attaches to the existing finding
  instead of opening a second one. Severity only rises, `last_seen_at` only moves forward
  (events can arrive out of order), and status is left alone, so a SUPPRESSED finding
  stays suppressed.
- **Recurrence:** RESOLVED findings never match. An event for a resolved problem opens a
  new finding, and the resolved one is kept as history.

Checks run in this order: validation, then detection (`ignored`), then the duplicate check,
then the match against an OPEN or SUPPRESSED finding. Ignored events are never stored, so
resending one returns `ignored` again, never `duplicate`. Everything stored for one event,
the finding and the event row, is committed in one transaction. See
[data-model.md](./data-model.md) for fingerprints and the partial unique index.

**Errors:** a body that is valid JSON but not a valid CloudTrail record returns `422
invalid_event`. Its `details.fields` locations use CloudTrail's field names, with no
`body` prefix, because the service validates the record itself:

```json
{
  "error": {
    "code": "invalid_event",
    "message": "CloudTrail event failed validation.",
    "details": {
      "fields": [
        {"loc": ["eventTime"], "msg": "Input should be a valid datetime or date, ...", "type": "datetime_from_date_parsing"}
      ]
    }
  }
}
```

A body that isn't a JSON object at all is rejected earlier, by FastAPI, with `422
validation_error`.

### Findings

Read and status endpoints are added in card 1.6.

---

## Pagination, Filtering, and Sorting

Defined with the list endpoint in card 1.6.

---

## Errors

Every error, of any kind, returns the same shape:

```json
{
  "error": {
    "code": "finding_not_found",
    "message": "No finding with id 3f2a...",
    "details": null
  }
}
```

- **`code`:** a stable, machine-readable string. Clients branch on it; it never changes
  even if the wording does.
- **`message`:** a human-readable explanation.
- **`details`:** an object with extra information, or `null`. It is always an object when
  present, so new keys can be added without breaking clients.

A request that fails validation returns `422` with the invalid fields under
`details.fields`. Only each field's location, message, and type are returned; the
submitted value is never echoed back.

```json
{
  "error": {
    "code": "validation_error",
    "message": "Request validation failed.",
    "details": {
      "fields": [
        {"loc": ["body", "eventName"], "msg": "Field required", "type": "missing"}
      ]
    }
  }
}
```

| Status | `code` | When |
|---|---|---|
| 404 | `not_found` | No route matches the path |
| 404 | `finding_not_found` | The finding does not exist (1.6) |
| 405 | `method_not_allowed` | The path exists, but not for this method |
| 422 | `validation_error` | The request body or parameters fail validation |
| 422 | `invalid_event` | A CloudTrail event failed validation during ingest (sanitized field errors in `details.fields`) |
| 500 | `internal_error` | An unexpected error. The message is generic; the traceback is logged server-side and never returned |
| 503 | `service_unavailable` | A dependency is down, e.g. `/ready` when the database is unreachable |

Any other HTTP status that reaches the API layer is returned with code `http_error`.

**How it works:** services raise subclasses of `AppError` (`core/exceptions.py`), which
carry their own status and code and import nothing from FastAPI, so the Phase 2 consumer
can reuse the same services without HTTP. The handlers in `api/errors.py` convert every
exception (`AppError`, validation errors, HTTP errors, and anything unexpected) into the
shape above.

---

## Asynchronous Operations

None in Phase 1; ingest runs inline. In Phase 2, events arrive through EventBridge, SNS,
and SQS, and the consumer calls the same ingest service directly rather than this API.

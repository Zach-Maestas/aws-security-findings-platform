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

Ingest is added in card 1.4. It accepts one CloudTrail record and reports what happened to
it (a finding created or updated, a duplicate skipped, or the event ignored).

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

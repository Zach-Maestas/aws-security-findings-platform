# API Reference

<!-- The contract the backend exposes. Interactive docs are served by FastAPI at
     /docs; this file covers the conventions and reasoning the schema can't show. -->

---

## Conventions

<!-- Base path and versioning (/api/v1), content types, naming, timestamps (UTC, ISO 8601),
     and how breaking changes are handled. -->

---

## Authentication and Authorization

<!-- How a caller proves identity, how roles/permissions map to endpoints.
     Link to security.md for the design rationale. -->

---

## Endpoints

<!-- One subsection per resource. For each endpoint: method + path, purpose,
     required permission, and notable status codes. -->

### Findings

| Method | Path | Purpose | Permission |
|---|---|---|---|
| | | | |

### Events

| Method | Path | Purpose | Permission |
|---|---|---|---|
| | | | |

### Health

| Method | Path | Purpose |
|---|---|---|
| | | |

---

## Pagination, Filtering, and Sorting

---

## Errors

<!-- The error response shape, and the status codes the API uses and what they mean. -->

```json
```

| Status | When |
|---|---|
| | |

---

## Asynchronous Operations

<!-- Endpoints that enqueue work instead of doing it inline: what they return (e.g. 202),
     how a caller tracks the result, and idempotency keys if used. -->

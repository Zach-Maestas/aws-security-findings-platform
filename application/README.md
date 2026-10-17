# Findings Platform API

FastAPI service that records CloudTrail-derived security findings in PostgreSQL,
deduplicates repeat events, and tracks each finding's status.

For the data model and API contract, see [docs/data-model.md](../docs/data-model.md)
and [docs/api.md](../docs/api.md).

## Prerequisites

- [uv](https://docs.astral.sh/uv/) 0.13.1
- Docker
- Python 3.13 (uv installs it automatically if missing)

## Running Locally

All commands run from the `application/` directory.

**Development server** (auto-reloads on code changes):

```bash
uv sync
uv run uvicorn findings_platform.main:app --reload
```

**Container** (production-style, no reload):

```bash
docker build -t findings-api .
docker run --rm -p 8000:8000 findings-api
```

Either way, the interactive API docs are at http://localhost:8000/docs.
Logs are written to stdout as JSON.

**Environment:** settings are read from environment variables, with defaults for
everything, so no `.env` file is needed to run. To override values locally, copy
`.env.example` to `.env`. In AWS, the same variables are set by the ECS task definition.

| Variable | Default | Purpose |
|---|---|---|
| `APP_NAME` | `AWS Security Findings Platform` | Title shown in the API docs |
| `LOG_LEVEL` | `INFO` | Minimum log level (`DEBUG`, `INFO`, `WARNING`, `ERROR`) |

## Database Migrations

<!-- Generating and applying Alembic migrations locally -->

```bash
```

## Running Tests

<!-- Unit and integration tests, lint and format -->

```bash
```

## Project Layout

```
src/findings_platform/
├── main.py      # creates the FastAPI app and mounts the routers
├── api/         # HTTP routes: business endpoints under v1/; /health and /ready unversioned
├── core/        # settings, custom exceptions, and JSON logging setup
├── db/          # database engine and session setup
├── models/      # SQLAlchemy models (database tables)
├── schemas/     # Pydantic models for request and response JSON
└── services/    # business logic: parsing events, fingerprinting, matching findings
```

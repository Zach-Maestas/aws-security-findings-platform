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

First, copy `.env.example` to `.env` and set `POSTGRES_PASSWORD` (and the matching
password in `DATABASE_URL`).

**Full stack in Docker** (Postgres, migrations, then the API):

```bash
docker compose up -d --build
```

Compose starts Postgres, runs `alembic upgrade head` in a one-off `migrate` container,
and starts the API only after migrations succeed. `docker compose down` stops it;
`docker compose down -v` also deletes the database volume.

**Development server** (auto-reloads on code changes), with Postgres from compose:

```bash
uv sync
docker compose up -d db
uv run alembic upgrade head
uv run uvicorn findings_platform.main:app --reload
```

Either way, the interactive API docs are at http://localhost:8000/docs.
Logs are written to stdout as JSON.

**Environment:** settings are read from environment variables, or from `.env` when
running on the host. In compose, the containers get their values from
`docker-compose.yml`. In AWS, the same variables are set by the ECS task definition.

| Variable | Default | Purpose |
|---|---|---|
| `DATABASE_URL` | none (required) | SQLAlchemy URL for the app and Alembic. On the host it points at `localhost:5432`; compose builds its own with host `db` |
| `POSTGRES_USER`, `POSTGRES_PASSWORD`, `POSTGRES_DB` | `findings_user`, none (required), `findings` | Used by compose to initialize Postgres and build the containers' `DATABASE_URL` |
| `APP_NAME` | `AWS Security Findings Platform` | Title shown in the API docs |
| `LOG_LEVEL` | `INFO` | Minimum log level (`DEBUG`, `INFO`, `WARNING`, `ERROR`) |

## Database Migrations

`docker compose up` applies pending migrations automatically. On the host, with
Postgres running:

```bash
uv run alembic upgrade head                                   # apply pending migrations
uv run alembic current                                        # show the applied revision
uv run alembic revision --autogenerate -m "describe change"   # new migration from model changes
uv run alembic downgrade -1                                   # undo the latest migration
```

Review every generated migration before applying it. The workflow, review checklist,
and rules are in [docs/data-model.md](../docs/data-model.md#migrations).

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

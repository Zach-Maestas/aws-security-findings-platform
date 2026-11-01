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

The `Makefile` at the repository root runs the same checks CI runs:

```bash
make app-fix       # fix lint issues and format code (changes files)
make app-check     # ruff check + ruff format --check (changes nothing)
make test          # start the test database, then run every test
make test-db-down  # stop the test database
```

Or directly, from `application/`:

```bash
docker compose --profile test up -d --wait test-db
uv run pytest                     # everything
uv run pytest tests/unit          # no database needed
uv run pytest tests/integration   # needs test-db
```

**Unit vs. integration:** a test that needs the database goes in `tests/integration/`;
everything else goes in `tests/unit/`. Unit tests run with nothing else running.

**The test database** is a separate `test-db` compose service: Postgres on port 5433,
database `findings_test`, data in memory (`tmpfs`), started only with the `test` profile.
It never touches the dev database on port 5432. CI uses an equivalent Postgres service
container. Point tests elsewhere with `TEST_DATABASE_URL`.

**How integration tests stay isolated** (`tests/integration/conftest.py`):

- The `engine` fixture refuses any database whose name doesn't end in `_test`, then runs
  `alembic upgrade head` once per test run, so the migrations are tested too.
- Each test gets a `db_session` inside an outer transaction that is rolled back
  afterwards. The session joins it with `create_savepoint`, so a `commit()` in application
  code releases a savepoint instead of committing, and every test starts empty.
- The integration `client` overrides `get_db`, so endpoints use that session.

**Fixtures:** CloudTrail records in `tests/fixtures/cloudtrail/`, listed with their
expected results in [docs/data-model.md](../docs/data-model.md#test-fixtures).

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

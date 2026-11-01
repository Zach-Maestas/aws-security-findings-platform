import os
from pathlib import Path

import pytest
from alembic import command
from alembic.config import Config
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.engine import make_url
from sqlalchemy.orm import Session

from findings_platform.api.deps import get_db
from findings_platform.main import app

# Defaults to the docker-compose test Postgres (port 5433, separate from the dev DB).
TEST_DATABASE_URL = os.environ.get(
    "TEST_DATABASE_URL",
    "postgresql+psycopg://test:test@localhost:5433/findings_test",
)
# parents[2] climbs tests/integration/ -> tests/ -> application/ (holds alembic.ini).
ALEMBIC_INI = Path(__file__).resolve().parents[2] / "alembic.ini"


def _apply_migrations():
    """Build the test schema with the real migrations, not Base.metadata.create_all().

    Running Alembic means the tests also catch broken or missing migrations.
    """
    cfg = Config(str(ALEMBIC_INI))

    # Alembic's config parser treats "%" as interpolation syntax, so a
    # URL-encoded password (e.g. "p%40ss") must be escaped as "%%".
    cfg.set_main_option("sqlalchemy.url", TEST_DATABASE_URL.replace("%", "%%"))

    command.upgrade(cfg, "head")


@pytest.fixture(scope="session")
def engine():
    # Safety guard: these tests write to the database, so refuse to run
    # against anything that isn't clearly a throwaway test database.
    db_name = make_url(TEST_DATABASE_URL).database or ""
    if not db_name.endswith("_test"):
        pytest.fail(
            "TEST_DATABASE_URL must point at a database whose name ends in "
            f'"_test" (got "{db_name}"). Set TEST_DATABASE_URL to a test database.'
        )

    # Migrate once per test run; session scope shares the engine across all tests.
    _apply_migrations()

    test_engine = create_engine(TEST_DATABASE_URL)

    yield test_engine

    # Close pooled connections so Postgres isn't left with idle sessions.
    test_engine.dispose()


@pytest.fixture
def db_session(engine):
    """Give each test a session whose changes are rolled back afterwards.

    An outer transaction wraps the whole test. "create_savepoint" makes any
    session.commit() in app code release a SAVEPOINT instead of truly
    committing, so the final rollback discards everything and tests stay isolated.
    """
    with engine.connect() as conn:
        transaction = conn.begin()
        with Session(bind=conn, join_transaction_mode="create_savepoint") as session:
            yield session

        transaction.rollback()


@pytest.fixture
def client(db_session):
    # Make the API use the test's rollback-wrapped session instead of
    # SessionLocal, so requests and test assertions see the same data.
    def override_get_db():
        yield db_session

    app.dependency_overrides[get_db] = override_get_db

    with TestClient(app) as test_client:
        yield test_client

    # Reset overrides so they don't leak into other tests using the global app.
    app.dependency_overrides.clear()

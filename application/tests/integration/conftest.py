import os
from pathlib import Path

import pytest
from alembic import command
from alembic.config import Config
from fastapi.testclient import TestClient
from findings_platform.api.deps import get_db
from findings_platform.main import app
from sqlalchemy import create_engine
from sqlalchemy.engine import make_url
from sqlalchemy.orm import Session

TEST_DATABASE_URL = os.environ.get(
    "TEST_DATABASE_URL",
    "postgresql+psycopg://test:test@localhost:5433/findings_test",
)
ALEMBIC_INI = Path(__file__).resolve().parents[2] / "alembic.ini"


def apply_migrations():
    cfg = Config(str(ALEMBIC_INI))

    cfg.set_main_option("sqlalchemy.url", TEST_DATABASE_URL.replace("%", "%%"))

    command.upgrade(cfg, "head")


@pytest.fixture(scope="session")
def engine():
    db_name = make_url(TEST_DATABASE_URL).database or ""
    if not db_name.endswith("_test"):
        pytest.fail(
            "TEST_DATABASE_URL must point at a database whose name ends in "
            f'"_test" (got "{db_name}"). Set TEST_DATABASE_URL to a test database.'
        )

    apply_migrations()

    test_engine = create_engine(TEST_DATABASE_URL)

    yield test_engine

    test_engine.dispose()


@pytest.fixture
def db_session(engine):
    with engine.connect() as conn:
        transaction = conn.begin()
        with Session(bind=conn, join_transaction_mode="create_savepoint") as session:
            yield session

        transaction.rollback()


@pytest.fixture
def client(db_session):
    def override_get_db():
        yield db_session

    app.dependency_overrides[get_db] = override_get_db

    with TestClient(app) as test_client:
        yield test_client

    app.dependency_overrides.clear()

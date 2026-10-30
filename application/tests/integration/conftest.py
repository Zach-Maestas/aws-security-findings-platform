import os
from pathlib import Path

import pytest
from alembic import command
from alembic.config import Config
from sqlalchemy import create_engine
from sqlalchemy.engine import make_url

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

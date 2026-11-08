import json
from pathlib import Path
from typing import Any

import pytest
from fastapi.testclient import TestClient

from findings_platform.main import app

CLOUDTRAIL_FIXTURES = Path(__file__).parent / "fixtures" / "cloudtrail"


@pytest.fixture
def client():
    with TestClient(app) as test_client:
        yield test_client


@pytest.fixture
def load_cloudtrail():
    """Return a function that loads a CloudTrail fixture by name, as a raw dict."""

    def load(name: str) -> dict[str, Any]:
        return json.loads((CLOUDTRAIL_FIXTURES / f"{name}.json").read_text())

    return load


def pytest_generate_tests(metafunc):
    """Run any test that takes `cloudtrail_path` once per fixture file."""
    if "cloudtrail_path" in metafunc.fixturenames:
        paths = sorted(CLOUDTRAIL_FIXTURES.glob("*.json"))
        # Use file stems as test IDs so a failure names the fixture, e.g.
        # test_parse[sg_open_world_ipv4_ssh] instead of
        # test_parse[cloudtrail_path0].
        metafunc.parametrize("cloudtrail_path", paths, ids=[p.stem for p in paths])

import pytest
from fastapi.testclient import TestClient

from findings_platform.main import app


@pytest.fixture
def client():
    with TestClient(app) as test_client:
        yield test_client

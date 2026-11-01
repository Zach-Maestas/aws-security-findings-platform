import json
from datetime import datetime
from pathlib import Path

import pytest

from findings_platform.schemas.event import CloudTrailEvent

FIXTURES = Path(__file__).resolve().parents[1] / "fixtures" / "cloudtrail"


def load(name):
    return CloudTrailEvent.model_validate(
        json.loads((FIXTURES / f"{name}.json").read_text())
    )


# Verifies each CloudTrail event from tests/fixtures/ matches the event schema
@pytest.mark.parametrize("path", sorted(FIXTURES.glob("*.json")), ids=lambda p: p.stem)
def test_fixture_validates(path):
    event = CloudTrailEvent.model_validate(json.loads(path.read_text()))
    assert event.event_id


@pytest.mark.parametrize("path", sorted(FIXTURES.glob("*.json")), ids=lambda p: p.stem)
def test_event_time_is_datetime(path):
    event = CloudTrailEvent.model_validate(json.loads(path.read_text()))
    assert isinstance(event.event_time, datetime)


def test_assumed_role_identity_maps():
    event = load("sg_open_world_ipv4_all_assumed_role")
    assert event.user_identity.identity_type == "AssumedRole"
    assert event.user_identity.arn.startswith("arn:aws:sts::")


def test_aws_service_has_no_arn():
    event = load("sg_open_world_ipv4_ssh_aws_service")
    assert event.user_identity.arn is None
    assert event.user_identity.invoked_by == "ec2.amazonaws.com"


def test_failed_call_keeps_error_code():
    event = load("iam_attach_admin_role_access_denied")
    assert event.error_code == "AccessDenied"

import json
from datetime import datetime

from findings_platform.schemas.event import CloudTrailEvent


def test_fixture_validates(cloudtrail_path):
    event = CloudTrailEvent.model_validate(json.loads(cloudtrail_path.read_text()))
    assert event.event_id


def test_event_time_is_datetime(cloudtrail_path):
    event = CloudTrailEvent.model_validate(json.loads(cloudtrail_path.read_text()))
    assert isinstance(event.event_time, datetime)


def test_assumed_role_identity_maps(load_cloudtrail):
    event = CloudTrailEvent.model_validate(
        load_cloudtrail("sg_open_world_ipv4_all_assumed_role")
    )
    assert event.user_identity.identity_type == "AssumedRole"
    assert event.user_identity.arn.startswith("arn:aws:sts::")


def test_aws_service_has_no_arn(load_cloudtrail):
    event = CloudTrailEvent.model_validate(
        load_cloudtrail("sg_open_world_ipv4_ssh_aws_service")
    )
    assert event.user_identity.arn is None
    assert event.user_identity.invoked_by == "ec2.amazonaws.com"


def test_failed_call_keeps_error_code(load_cloudtrail):
    event = CloudTrailEvent.model_validate(
        load_cloudtrail("iam_attach_admin_role_access_denied")
    )
    assert event.error_code == "AccessDenied"

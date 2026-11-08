from findings_platform.models.enums import DetectionType, Severity
from findings_platform.services.detection import dispatch
from findings_platform.services.detection.types import Detection, Ignored, IgnoreReason
from findings_platform.services.parsing import parse_event


def test_failed_call_is_ignored(load_cloudtrail):
    event = parse_event(load_cloudtrail("iam_attach_admin_role_access_denied"))

    assert dispatch.detect(event) == Ignored(
        IgnoreReason.ERROR_CODE, detail="AccessDenied"
    )


def test_handler_returning_none_is_not_risky(load_cloudtrail, monkeypatch):
    monkeypatch.setitem(
        dispatch.HANDLERS, "AuthorizeSecurityGroupIngress", lambda event: None
    )
    event = parse_event(load_cloudtrail("sg_open_world_ipv4_ssh"))

    assert dispatch.detect(event) == Ignored(IgnoreReason.NOT_RISKY)


def test_unhandled_event_name_is_ignored(load_cloudtrail):
    raw = load_cloudtrail("sg_open_world_ipv4_ssh")
    raw["eventName"] = "DescribeInstances"  # a read-only call no detection will handle
    event = parse_event(raw)

    assert dispatch.detect(event) == Ignored(
        IgnoreReason.UNHANDLED_EVENT_NAME, detail="DescribeInstances"
    )


def test_handler_detection_is_returned(load_cloudtrail, monkeypatch):
    expected = Detection(
        detection_type=DetectionType.SG_OPEN_TO_WORLD,
        severity=Severity.HIGH,
        fingerprint="SG_OPEN_TO_WORLD|test",
        resource="arn:aws:ec2:us-east-1:111122223333:security-group/sg-test",
        account="111122223333",
        region="us-east-1",
    )
    monkeypatch.setitem(
        dispatch.HANDLERS, "AuthorizeSecurityGroupIngress", lambda event: expected
    )
    event = parse_event(load_cloudtrail("sg_open_world_ipv4_ssh"))

    assert dispatch.detect(event) is expected

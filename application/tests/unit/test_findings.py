from dataclasses import replace
from datetime import timedelta

from findings_platform.models.enums import Severity, Status, SuppressionReason
from findings_platform.services.detection.dispatch import detect
from findings_platform.services.findings import _create_finding, _update_finding
from findings_platform.services.parsing import parse_event


def _finding_and_event(load_cloudtrail):
    """A finding built from the SG fixture, plus the event it came from."""
    event = parse_event(load_cloudtrail("sg_open_world_ipv4_ssh"))
    detection = detect(event)
    return _create_finding(detection, event), detection, event


def test_older_event_does_not_move_last_seen_at_back(load_cloudtrail):
    finding, detection, event = _finding_and_event(load_cloudtrail)
    older = event.model_copy(
        update={"event_time": event.event_time - timedelta(hours=1)}
    )

    _update_finding(finding, detection, older)

    assert finding.last_seen_at == event.event_time


def test_newer_event_moves_last_seen_at_forward(load_cloudtrail):
    finding, detection, event = _finding_and_event(load_cloudtrail)
    newer = event.model_copy(
        update={"event_time": event.event_time + timedelta(hours=1)}
    )

    _update_finding(finding, detection, newer)

    assert finding.last_seen_at == newer.event_time


def test_higher_severity_raises_finding_severity(load_cloudtrail):
    finding, detection, event = _finding_and_event(load_cloudtrail)
    finding.severity = Severity.MEDIUM

    _update_finding(finding, replace(detection, severity=Severity.HIGH), event)

    assert finding.severity is Severity.HIGH


def test_lower_severity_does_not_downgrade_finding(load_cloudtrail):
    finding, detection, event = _finding_and_event(load_cloudtrail)
    finding.severity = Severity.HIGH

    _update_finding(finding, replace(detection, severity=Severity.MEDIUM), event)

    assert finding.severity is Severity.HIGH


def test_update_leaves_suppressed_status_alone(load_cloudtrail):
    finding, detection, event = _finding_and_event(load_cloudtrail)
    finding.status = Status.SUPPRESSED
    finding.suppression_reason = SuppressionReason.ACCEPTED_RISK

    _update_finding(finding, detection, event)

    assert finding.status is Status.SUPPRESSED
    assert finding.suppression_reason is SuppressionReason.ACCEPTED_RISK

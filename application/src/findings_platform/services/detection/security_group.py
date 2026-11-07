from dataclasses import dataclass
from typing import Any

from findings_platform.models.enums import DetectionType, Severity
from findings_platform.schemas.event import CloudTrailEvent
from findings_platform.services.detection.types import Detection

_RISKY_PORTS = (22, 3389)


@dataclass(frozen=True)
class Rule:
    protocol: str  # "tcp", "udp", "icmp", or "-1" for all traffic
    from_port: int | None  # None when the protocol is "-1" (no ports given)
    to_port: int | None
    cidr: str  # e.g. "0.0.0.0/0" or "::/0"


def _rules_from_authorize(params: dict[str, Any]) -> list[Rule]:
    """One Rule per CIDR source in an AuthorizeSecurityGroupIngress request.

    Group sources are skipped: they mean "instances in that group", never the
    internet. Prefix-list sources are skipped too: their CIDRs aren't in the
    event (a known limitation, see docs/security.md).
    """
    rules: list[Rule] = []

    for perm in params.get("ipPermissions", {}).get("items", []):
        protocol = perm.get("ipProtocol")
        from_port = perm.get("fromPort")
        to_port = perm.get("toPort")

        for entry in perm.get("ipRanges", {}).get("items", []):
            rules.append(Rule(protocol, from_port, to_port, entry["cidrIp"]))

        for entry in perm.get("ipv6Ranges", {}).get("items", []):
            rules.append(Rule(protocol, from_port, to_port, entry["cidrIpv6"]))

    return rules


def _rules_from_modify(params: dict[str, Any]) -> list[Rule]:
    pass


def _rule_severity(rule: Rule) -> Severity | None:
    """The severity of one rule if it's open to the world, otherwise None."""
    if rule.cidr != "0.0.0.0/0" and rule.cidr != "::/0":
        return None
    if rule.protocol in ("-1", "all"):
        return Severity.CRITICAL
    if rule.protocol in ("tcp", "udp", "6", "17"):
        # Ports unknown, so assume the range could include a risky port.
        if rule.from_port is None or rule.to_port is None:
            return Severity.HIGH
        if any(rule.from_port <= port <= rule.to_port for port in _RISKY_PORTS):
            return Severity.HIGH
    return Severity.MEDIUM


def _detect_open_rules(
    event: CloudTrailEvent,
    group_ref: str | None,
    rules: list[Rule],
) -> Detection | None:
    """Turn the worst world-open rule into a Detection, or None if nothing is open.

    group_ref is the group's ID or name, chosen by the caller. Returns None
    without one, since there's no resource to build a fingerprint from.
    """
    if not group_ref:
        return None

    severities = [s for rule in rules if (s := _rule_severity(rule)) is not None]
    if not severities:
        return None

    highest_severity = max(severities, key=lambda s: s.rank)
    resource = (
        f"arn:aws:ec2:{event.aws_region}:{event.recipient_account_id}:"
        f"security-group/{group_ref}"
    )
    fingerprint = f"{DetectionType.SG_OPEN_TO_WORLD.value}|{resource}"

    return Detection(
        detection_type=DetectionType.SG_OPEN_TO_WORLD,
        severity=highest_severity,
        fingerprint=fingerprint,
        resource=resource,
        account=event.recipient_account_id,
        region=event.aws_region,
    )


def handle_sg_authorize(event: CloudTrailEvent) -> Detection | None:
    """Detect world-open rules added by AuthorizeSecurityGroupIngress.

    Identifies the group by groupId, falling back to groupName for
    default-VPC requests.
    """
    params = event.request_parameters or {}
    group_ref = params.get("groupId") or params.get("groupName")
    rules = _rules_from_authorize(params)

    return _detect_open_rules(event, group_ref, rules)


def handle_sg_modify(event: CloudTrailEvent) -> Detection | None:
    pass

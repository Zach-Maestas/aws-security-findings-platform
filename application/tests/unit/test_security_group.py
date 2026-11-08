import pytest

from findings_platform.models.enums import DetectionType, Severity
from findings_platform.services.detection.dispatch import detect
from findings_platform.services.detection.security_group import (
    Rule,
    _detect_open_rules,
    _rule_severity,
    _rules_from_authorize,
    _rules_from_modify,
)
from findings_platform.services.detection.types import Detection, Ignored, IgnoreReason
from findings_platform.services.parsing import parse_event

ACCOUNT = "111122223333"
REGION = "us-east-1"


@pytest.mark.parametrize(
    "rule, expected",
    [
        (Rule("tcp", 22, 22, "0.0.0.0/0"), Severity.HIGH),
        (Rule("tcp", 22, 22, "::/0"), Severity.HIGH),
        (Rule("tcp", 22, 22, "203.0.113.10/32"), None),
        (Rule("-1", None, None, "0.0.0.0/0"), Severity.CRITICAL),
        (Rule("tcp", 443, 443, "0.0.0.0/0"), Severity.MEDIUM),
        (Rule("tcp", 20, 25, "0.0.0.0/0"), Severity.HIGH),
        (Rule("6", 22, 22, "0.0.0.0/0"), Severity.HIGH),
        (Rule("icmp", 0, 255, "0.0.0.0/0"), Severity.MEDIUM),
        # Ports unknown, so assume they could cover SSH/RDP.
        (Rule("tcp", None, None, "0.0.0.0/0"), Severity.HIGH),
    ],
    ids=[
        "ssh_ipv4_open",
        "ssh_ipv6_open",
        "ssh_single_ip",
        "all_traffic_open",
        "https_open",
        "port_range_covers_ssh",
        "numeric_tcp_ssh",
        "icmp_not_port_checked",
        "tcp_no_ports_open",
    ],
)
def test_rule_severity(rule, expected):
    assert _rule_severity(rule) == expected


def test_rules_from_authorize_real_event(load_cloudtrail):
    params = load_cloudtrail("sg_open_world_ipv4_ssh")["requestParameters"]
    assert _rules_from_authorize(params) == [Rule("tcp", 22, 22, "0.0.0.0/0")]


def test_rules_from_authorize_ipv4_and_ipv6():
    params = {
        "ipPermissions": {
            "items": [
                {
                    "ipProtocol": "tcp",
                    "fromPort": 22,
                    "toPort": 22,
                    "ipRanges": {"items": [{"cidrIp": "0.0.0.0/0"}]},
                    "ipv6Ranges": {"items": [{"cidrIpv6": "::/0"}]},
                }
            ]
        }
    }
    assert _rules_from_authorize(params) == [
        Rule("tcp", 22, 22, "0.0.0.0/0"),
        Rule("tcp", 22, 22, "::/0"),
    ]


def test_rules_from_authorize_group_source_only():
    params = {
        "ipPermissions": {
            "items": [
                {
                    "ipProtocol": "tcp",
                    "fromPort": 5432,
                    "toPort": 5432,
                    "groups": {"items": [{"groupId": "sg-0aaaaaaaaaaaaaaaa"}]},
                }
            ]
        }
    }

    assert _rules_from_authorize(params) == []


def test_rules_from_authorize_empty():
    assert _rules_from_authorize({}) == []


def test_rules_from_modify_single_rule(load_cloudtrail):
    # One modified rule: CloudTrail logs SecurityGroupRule as a dict.
    params = load_cloudtrail("sg_modify_open_world_ipv4_all_assumed_role")[
        "requestParameters"
    ]
    assert _rules_from_modify(params) == [Rule("-1", None, None, "0.0.0.0/0")]


def test_rules_from_modify_multiple_rules(load_cloudtrail):
    # Several modified rules in one call: CloudTrail logs a list.
    params = load_cloudtrail("sg_modify_multiple_rules_assumed_role")[
        "requestParameters"
    ]
    assert _rules_from_modify(params) == [
        Rule("tcp", 21, 21, "0.0.0.0/0"),
        Rule("tcp", 21, 21, "::/0"),
    ]


def test_rules_from_modify_group_source_only():
    params = {
        "ModifySecurityGroupRulesRequest": {
            "SecurityGroupRule": {
                "SecurityGroupRuleId": "sgr-0123456789abcdef9",
                "SecurityGroupRule": {
                    "IpProtocol": "tcp",
                    "FromPort": 5432,
                    "ToPort": 5432,
                    "ReferencedGroupId": "sg-0aaaaaaaaaaaaaaaa",
                },
            },
            "GroupId": "sg-0123456789abcdef9",
        }
    }
    assert _rules_from_modify(params) == []


def test_rules_from_modify_empty():
    assert _rules_from_modify({}) == []


def _sg_arn(group_id: str) -> str:
    return f"arn:aws:ec2:{REGION}:{ACCOUNT}:security-group/{group_id}"


# Expected results come from the fixtures table in docs/data-model.md.
SG_DETECTIONS = [
    ("sg_open_world_ipv4_ssh", Severity.HIGH),
    ("sg_open_world_ipv4_ssh_aws_service", Severity.HIGH),
    ("sg_open_world_ipv6_ssh", Severity.HIGH),
    ("sg_open_world_ipv4_all", Severity.CRITICAL),
    ("sg_open_world_ipv4_all_assumed_role", Severity.CRITICAL),
    ("sg_modify_open_world_ipv4_all_assumed_role", Severity.CRITICAL),
    ("sg_modify_multiple_rules_assumed_role", Severity.MEDIUM),
]


@pytest.mark.parametrize(
    "name, severity", SG_DETECTIONS, ids=[name for name, _ in SG_DETECTIONS]
)
def test_sg_fixture_detected(load_cloudtrail, name, severity):
    result = detect(parse_event(load_cloudtrail(name)))

    assert isinstance(result, Detection)
    assert result.detection_type is DetectionType.SG_OPEN_TO_WORLD
    assert result.severity is severity


SG_IGNORED = [
    ("sg_benign_single_ip", IgnoreReason.NOT_RISKY),
    ("sg_open_world_ipv4_ssh_access_denied", IgnoreReason.ERROR_CODE),
]


@pytest.mark.parametrize(
    "name, reason", SG_IGNORED, ids=[name for name, _ in SG_IGNORED]
)
def test_sg_fixture_ignored(load_cloudtrail, name, reason):
    result = detect(parse_event(load_cloudtrail(name)))

    assert isinstance(result, Ignored)
    assert result.reason is reason


def test_sg_authorize_detection_fields(load_cloudtrail):
    result = detect(parse_event(load_cloudtrail("sg_open_world_ipv4_ssh")))
    resource = _sg_arn("sg-0123456789abcdef0")

    assert result == Detection(
        detection_type=DetectionType.SG_OPEN_TO_WORLD,
        severity=Severity.HIGH,
        fingerprint=f"SG_OPEN_TO_WORLD|{resource}",
        resource=resource,
        account=ACCOUNT,
        region=REGION,
    )


def test_sg_modify_uses_group_id_inside_request(load_cloudtrail):
    # Modify nests GroupId under ModifySecurityGroupRulesRequest, unlike Authorize.
    result = detect(
        parse_event(load_cloudtrail("sg_modify_open_world_ipv4_all_assumed_role"))
    )

    assert isinstance(result, Detection)
    assert result.resource == _sg_arn("sg-0123456789abcdef4")


def test_detect_open_rules_picks_worst_severity(load_cloudtrail):
    event = parse_event(load_cloudtrail("sg_open_world_ipv4_ssh"))
    rules = [
        Rule("tcp", 443, 443, "0.0.0.0/0"),  # MEDIUM
        Rule("tcp", 22, 22, "0.0.0.0/0"),  # HIGH
        Rule("tcp", 22, 22, "203.0.113.10/32"),  # not open
    ]

    result = _detect_open_rules(event, "sg-0123456789abcdef0", rules)

    assert result is not None
    assert result.severity is Severity.HIGH


def test_detect_open_rules_without_group_ref(load_cloudtrail):
    event = parse_event(load_cloudtrail("sg_open_world_ipv4_ssh"))
    rules = [Rule("tcp", 22, 22, "0.0.0.0/0")]

    assert _detect_open_rules(event, None, rules) is None

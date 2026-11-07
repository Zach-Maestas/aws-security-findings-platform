import pytest

from findings_platform.models.enums import Severity
from findings_platform.services.detection.security_group import (
    Rule,
    _rule_severity,
    _rules_from_authorize,
)


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

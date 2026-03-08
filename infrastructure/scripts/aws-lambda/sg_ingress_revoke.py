import logging
import os

import boto3
from botocore.exceptions import ClientError

# Initialize logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

logger.info("lambda_starting")

# Initialize EC2 for Security Group management & SNS for alerts
ec2 = boto3.client("ec2")
sns = boto3.client("sns")

# Set SNS topic ARN
TOPIC_ARN = os.environ["SNS_TOPIC_ARN"]

# Ports and CIDRs that trigger automated revocation
DANGEROUS_PORTS = {22, 3389}
DANGEROUS_CIDRS = {"0.0.0.0/0", "::/0"}


# Revoke each dangerous rule from the security group via boto3
def revoke_dangerous_rules(sg_id, rules):
    for rule in rules:
        permission = {
            "IpProtocol": rule["ipProtocol"],
            "IpRanges": [{"CidrIp": r["cidrIp"]} for r in rule.get("ipRanges", {}).get("items", [])],
            "Ipv6Ranges": [{"CidrIpv6": r["cidrIpv6"]} for r in rule.get("ipv6Ranges", {}).get("items", [])]
        }

        # Protocol -1 (all traffic) has no port fields
        if rule.get("ipProtocol") != "-1":
            permission["FromPort"] = rule["fromPort"]
            permission["ToPort"] = rule["toPort"]

        ec2.revoke_security_group_ingress(
            GroupId=sg_id,
            IpPermissions=[permission]
        )

        port_range = "ALL" if rule.get("ipProtocol") == "-1" else f"{rule['fromPort']}-{rule['toPort']}"
        logger.info(
            "✅ Security Group Rule Revoked:\n[SG ID: %s]\n[IP Protocol: %s]\n[Port Range: %s]\n[IPv4 CIDRs: %s]\n[IPv6 CIDRS: %s]",
            sg_id,
            rule["ipProtocol"],
            port_range,
            [r["cidrIp"] for r in rule.get("ipRanges", {}).get("items", [])],
            [r["cidrIpv6"] for r in rule.get("ipv6Ranges", {}).get("items", [])]
            )

# Filter ipPermissions to only rules with dangerous port/CIDR combinations
def get_dangerous_rules(ip_perms):
    dangerous_rules = []

    for item in ip_perms["items"]:
        ipv4_cidrs = [r["cidrIp"] for r in item.get("ipRanges", {}).get("items", [])]
        ipv6_cidrs = [r["cidrIpv6"] for r in item.get("ipv6Ranges", {}).get("items", [])]

        has_dangerous_cidr = any(cidr in ipv4_cidrs or cidr in ipv6_cidrs for cidr in DANGEROUS_CIDRS)
        if not has_dangerous_cidr:
            continue

        # Protocol -1 means all traffic (all ports) — always dangerous with open CIDRs
        if item.get("ipProtocol") == "-1":
            dangerous_rules.append(item)
            continue

        from_port, to_port = int(item["fromPort"]), int(item["toPort"])
        if any(from_port <= port <= to_port for port in DANGEROUS_PORTS):
            dangerous_rules.append(item)
        
    return dangerous_rules

def send_sns_alert(alert_msg):
    sns.publish(
        TopicArn=TOPIC_ARN,
        Message=alert_msg,
        Subject="AWS Security Alert: Automated Remediation Triggered"
    )

# Entry point: triggered by EventBridge on AuthorizeSecurityGroupIngress events
def handler(event, context):
    try:
        principal_arn = event["detail"]["userIdentity"]["arn"]
        sg_id = event["detail"]["requestParameters"]["groupId"]
        ip_permissions = event["detail"]["requestParameters"]["ipPermissions"]

        if dangerous_rules := get_dangerous_rules(ip_permissions):
            logger.warning("⚠️ [%d] dangerous SG rule(s) attached by [%s] detected on [%s]", len(dangerous_rules), principal_arn, sg_id)
            
            revoke_dangerous_rules(sg_id, dangerous_rules)

            alert_msg = f"⚠️ {len(dangerous_rules)} dangerous SG rule(s) attached by [{principal_arn}] revoked from [{sg_id}]."
            
            send_sns_alert(alert_msg)
    except KeyError:
        logger.exception("❌ Event parsing failed:\n\n%s", event)
    except ClientError as e:
        error_code = e.response['Error']['Code']
        error_msg = e.response['Error']['Message']

        logger.error("❌ Failed: %s - %s", error_code, error_msg)
    except Exception:
        logger.exception("❌ An unexpected error occurred.")

import boto3
from botocore.exceptions import ClientError
import logging

# Initialize logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

logger.info("lambda_starting")

# Initialize EC2 for Security Group management
ec2 = boto3.client("ec2")

# Ports and CIDRs that trigger automated revocation
DANGEROUS_PORTS = {22, 3389}
DANGEROUS_CIDRS = {"0.0.0.0/0", "::/0"}


# Revoke each dangerous rule from the security group via boto3
def revoke_dangerous_rules(sg_id, rules):
    for rule in rules:
        ec2.revoke_security_group_ingress(
            GroupId=sg_id,
            IpPermissions=[
                {
                    "IpProtocol": rule["ipProtocol"],
                    "FromPort": rule["fromPort"],
                    "ToPort": rule["toPort"],
                    "IpRanges": [{"CidrIp": r["cidrIp"]} for r in rule.get("ipRanges", {}).get("items", [])],
                    "Ipv6Ranges": [{"CidrIpv6": r["cidrIpv6"]} for r in rule.get("ipv6Ranges", {}).get("items", [])]
                }
            ]
        )

        logger.info(
            "✅ Security Group Rule Revoked:\n[SG ID: %s]\n[IP Protocol: %s]\n[Port Range: %d-%d]\n[IPv4 CIDRs: %s]\n[IPv6 CIDRS: %s]", 
            sg_id, 
            rule["ipProtocol"], 
            rule["fromPort"], 
            rule["toPort"],
            [r["cidrIp"] for r in rule.get("ipRanges", {}).get("items", [])],
            [r["cidrIpv6"] for r in rule.get("ipv6Ranges", {}).get("items", [])]
            )

# Filter ipPermissions to only rules with dangerous port/CIDR combinations
def get_dangerous_rules(ip_perms):
    dangerous_rules = []

    for item in ip_perms["items"]:
        fromPort, toPort = int(item["fromPort"]), int(item["toPort"])
        ipv4_cidrs = [r["cidrIp"] for r in item.get("ipRanges", {}).get("items", [])]
        ipv6_cidrs = [r["cidrIpv6"] for r in item.get("ipv6Ranges", {}).get("items", [])]

        if any(fromPort <= port <= toPort for port in DANGEROUS_PORTS) and \
        any(cidr in ipv4_cidrs or cidr in ipv6_cidrs for cidr in DANGEROUS_CIDRS):
            dangerous_rules.append(item)
        
    return dangerous_rules


# Entry point: triggered by EventBridge on AuthorizeSecurityGroupIngress events
def handler(event, context):
    try:
        principal_arn = event["detail"]["userIdentity"]["arn"]
        sg_id = event["detail"]["requestParameters"]["groupId"]
        ip_permissions = event["detail"]["requestParameters"]["ipPermissions"]

        if dangerous_rules := get_dangerous_rules(ip_permissions):
            logger.warning("⚠️ Dangerous SG rule attachment(s) by [%s] detected on [%s]", principal_arn, sg_id)
            revoke_dangerous_rules(sg_id, dangerous_rules)
    except KeyError:
        logger.exception("❌ Event parsing failed:\n\n%s", event)
    except ClientError as e:
        error_code = e.response['Error']['Code']
        error_msg = e.response['Error']['Message']

        logger.error("❌ Failed: %s - %s", error_code, error_msg)
    except Exception:
        logger.exception("❌ An unexpected error occurred.")

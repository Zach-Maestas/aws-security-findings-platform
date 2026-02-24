import logging
import os

import boto3
from botocore.exceptions import ClientError


# Initialize logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

logger.info("lambda_starting")

# Initialize IAM for policy management & SNS for alerts
iam = boto3.client("iam")
sns = boto3.client("sns")

# Set SNS topic ARN
TOPIC_ARN = os.environ["SNS_TOPIC_ARN"]


# Revoke 'policy' from 'role'
def revoke_policy(role, policy):
    iam.detach_role_policy(
        RoleName=role,
        PolicyArn=policy
    )

def send_sns_alert(alert_msg):
    sns.publish(
        TopicArn=TOPIC_ARN,
        Message=alert_msg,
        Subject="AWS Security Alert: Automated Remediation Triggered"
    )


# Entry point: triggered by EventBridge on IAM AdministratorAccess attachment events
def handler(event, context):
    try:
        principal_arn = event["detail"]["userIdentity"]["arn"]
        role_name = event["detail"]["requestParameters"]["roleName"]
        policy_arn = event["detail"]["requestParameters"]["policyArn"]

        warning_msg = f"⚠️ AdministratorAccess attachment by [{principal_arn}] detected on role [{role_name}]. Policy has been automatically revoked."

        revoke_policy(role_name, policy_arn)
        send_sns_alert(warning_msg)
        logger.warning(warning_msg)
    except KeyError:
        logger.exception("❌ Event parsing failed:\n\n%s", event)
    except ClientError as e:
        error_code = e.response['Error']['Code']
        error_msg = e.response['Error']['Message']

        logger.error("❌ Failed: %s - %s", error_code, error_msg)
    except Exception:
        logger.exception("❌ An unexpected error occurred.")

import boto3
from botocore.exceptions import ClientError
import logging

# Initialize logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

logger.info("lambda_starting")

# Initialize IAM
iam = boto3.client("iam")


# Revoke 'policy' from 'role'
def revoke_policy(role, policy):
    iam.detach_role_policy(
        RoleName=role,
        PolicyArn=policy
    )


def handler(event, context):
    try:
        role_name = event["detail"]["requestParameters"]["roleName"]
        policy_arn = event["detail"]["requestParameters"]["policyArn"]

        revoke_policy(role_name, policy_arn)

        logger.info("✅ IAM Policy [%s] successfully revoked from role [%s]", policy_arn, role_name)
    except KeyError:
        logger.exception("❌ Event parsing failed:\n\n%s", event)
    except ClientError as e:
        error_code = e.response['Error']['Code']
        error_msg = e.response['Error']['Message']

        logger.error("❌ Failed: %s - %s", error_code, error_msg)
    except Exception:
        logger.exception("❌ An unexpected error occurred.")

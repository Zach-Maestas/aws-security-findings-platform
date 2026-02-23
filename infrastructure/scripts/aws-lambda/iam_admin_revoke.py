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


# Entry point: triggered by EventBridge on IAM AdministratorAccess attachment events
def handler(event, context):
    try:
        principal_arn = event["detail"]["userIdentity"]["arn"]
        role_name = event["detail"]["requestParameters"]["roleName"]
        policy_arn = event["detail"]["requestParameters"]["policyArn"]

        logger.warning("⚠️ AdministratorAccess attachment by [%s] detected on role [%s]", principal_arn, role_name)
        revoke_policy(role_name, policy_arn)
        logger.info("✅ IAM Policy [%s] revoked from role [%s]", policy_arn, role_name)
    except KeyError:
        logger.exception("❌ Event parsing failed:\n\n%s", event)
    except ClientError as e:
        error_code = e.response['Error']['Code']
        error_msg = e.response['Error']['Message']

        logger.error("❌ Failed: %s - %s", error_code, error_msg)
    except Exception:
        logger.exception("❌ An unexpected error occurred.")

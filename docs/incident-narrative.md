# Incident Narrative: Simulated Security Events 🚨

This document describes two simulated security incidents used to validate the automated detection and response pipelines.

---

## Incident 1: IAM Privilege Escalation

### Summary
An IAM role was created with the attached policy `AdministratorAccess`. This policy is highly privileged – granting full access to the entire AWS account. It should only be attached to the root user and rarely has any use cases in production.

### Timeline
- 10:53:43 PM --> Role created `secops-pipeline-test-role` with `AdministratorAccess` policy attached
- 10:53:45 PM --> Log stream and group created for Lambda function `secops-pipeline-iam-admin-policy-revoke`
- 10:53:45 PM --> `DetachRolePolicy` run by the Lambda function `secops-pipeline-iam-admin-policy-revoke` – detaching the policy `AdministratorAccess`

### Detection
The policy attachment was caught by EventBridge rule `secops-pipeline-capture-iam-admin-attachment`, the CloudTrail event that triggered it was `AttachRolePolicy` with the policy `AdministratorAccess`.

### Automated Response
The Lambda function called the IAM API via `iam.detach_role_policy(RoleName=role,PolicyArn=policy)`, detaching the AdministratorAccess policy from the `secops-pipeline-test-role` role.

### Evidence
<img src="./screenshots/phase2/cloudtrail_iam_admin_policy_attach_detach.png" height="800" width="800" /> 
<img src="./screenshots/phase2/cloudwatch_logs_lambda_iam_remediation.png" height="800" width="800" /> 
<img src="./screenshots/phase2/eventbridge_iam_admin_revoke_rule.png" height="800" width="800" /> 

### Lessons Learned
- Automated remediation of privilege escalation significantly reduces the window of exposure — the policy was detached within 2 seconds of attachment
- EventBridge's ability to match on specific `requestParameters` (like `policyArn`) allows precise detection without noisy false positives, unlike the SG pipeline which requires Lambda-side filtering
- In production, this should be paired with SNS alerting — a silent revocation could mask a compromised credential that continues attempting escalation
- The shared Lambda execution role means this function also carries EC2 permissions it doesn't need — separate roles per function would limit damage if the Lambda itself were compromised

---

## Incident 2: Dangerous Security Group Ingress

### Summary
A security group inbound rule was added allowing SSH (port 22) access from `0.0.0.0/0` — exposing the port to the entire internet. This is one of the most common misconfigurations in cloud environments and a leading attack vector for unauthorized access. The automated remediation pipeline detected and revoked the rule within seconds.

### Timeline
- 9:50:06 PM --> Security group `test-dangerous-sg` (`sg-0493fbf16ee19b7e7`) created by Zach
- 9:50:06 PM --> `AuthorizeSecurityGroupIngress` – SSH (port 22) from `0.0.0.0/0` added by Zach
- 9:50:07 PM --> `RevokeSecurityGroupEgress` – default outbound rule manually revoked by Zach
- 9:50:09 PM --> `RevokeSecurityGroupIngress` – Lambda function `secops-pipeline-sg-ingress-revoke` revokes the dangerous rule
- 9:50:11 PM --> Log group and stream created for Lambda function `secops-pipeline-sg-ingress-revoke`

### Detection
CloudTrail logged the `AuthorizeSecurityGroupIngress` API call, which triggered EventBridge rule `secops-pipeline-capture-sg-ingress`. Because EventBridge cannot filter on deeply nested fields like port numbers and CIDRs, the rule fires on all security group ingress changes. The Lambda function `secops-pipeline-sg-ingress-revoke` then inspected the event's `requestParameters` and determined the rule was dangerous: port 22 falls within the configured dangerous ports (22, 3389), and `0.0.0.0/0` matches the dangerous CIDRs list.

### Automated Response
The Lambda function called the EC2 API via `ec2.revoke_security_group_ingress()`, removing only the offending inbound rule. Other rules on the same security group were left intact — minimizing blast radius and avoiding disruption to any services attached to the security group.

### Evidence
<img src="./screenshots/phase2/sg_all_inbound_port_22_created.png" height="800" width="800" /> 
<img src="./screenshots/phase2/cloudtrail_sg_revoke_event_logs.png" height="800" width="800" />
<img src="./screenshots/phase2/cloudtrail_revoke_sg.png" height="800" width="800" /> 
<img src="./screenshots/phase2/cloudwatch_logs_revoke_sg.png" height="800" width="800" /> 
<img src="./screenshots/phase2/sg_rule_revoked.png" height="800" width="800" /> 

### Lessons Learned
- Automated remediation should be surgical — revoking individual rules rather than deleting entire security groups prevents collateral damage to running infrastructure
- Broad EventBridge triggers paired with precise Lambda filtering is a practical pattern when event structures are too deeply nested for EventBridge pattern matching
- In production, this pipeline should include SNS notification so security teams are alerted when remediation occurs — automated response without human awareness risks masking persistent threats

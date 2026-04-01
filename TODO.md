# TODO

## IAM Governance Rollout

- [x] Implement workload IAM role split for ECS, Lambda, and Step Functions.
- [x] Add human IAM roles: admin, devops, auditor, support_read_only.
- [x] Add CMK model with key policies: transaction_data_key, pii_data_key, logs_key.
- [x] Add IAM Identity Center permission set resources (opt-in).
- [x] Add Organizations SCP resources and optional attachments (opt-in).
- [x] Update IAM architecture diagram in terraform/iam-diagram.md.
- [x] Generate IAM report document for submission.

## Follow-up (Production Enablement)

- [ ] Set identity_center_instance_arn and enable_identity_center=true in production variables.
- [ ] Set organizations_scp_target_id and enable_organizations_governance=true in production variables.
- [ ] Replace default human role trust principal list with approved federated principal ARNs.
- [ ] Run terraform plan/apply in AWS account (non-LocalStack) and capture evidence screenshots for report.

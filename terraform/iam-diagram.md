# SBCbank IAM Diagram

This diagram reflects the IAM roles, trust relationships, governance controls, and primary permission paths currently defined in Terraform.

```mermaid
flowchart LR
  %% Trust principals
  ECSP[ecs-tasks.amazonaws.com]
  LBDP[lambda.amazonaws.com]
  SFP[states.amazonaws.com]
  VFLP[vpc-flow-logs.amazonaws.com]
  HUMP[Allowed Human Principals]

  %% IAM roles
  EEXR[ECS Task Execution Role]
  EACR[ECS Task Role: account]
  ETRR[ECS Task Role: transaction]
  ELRR[ECS Task Role: ledger]
  ESRR[ECS Task Role: statement]
  ENRR[ECS Task Role: notification]
  LNXR[Lambda Execution Role: notification]
  LFXR[Lambda Execution Role: fraud]
  SFR[Step Functions Role]
  VFLR[VPC Flow Logs Role]
  ADM[Human Role: admin]
  DVO[Human Role: devops]
  AUD[Human Role: auditor]
  SUP[Human Role: support_read_only]

  %% Identity Center (optional)
  IC[(IAM Identity Center Instance)]
  PSA[Permission Set: admin]
  PSD[Permission Set: devops]
  PSU[Permission Set: auditor]
  PSS[Permission Set: support_read_only]

  %% Organizations governance (optional)
  ORG[(AWS Organizations)]
  SCPR[SCP: deny_root_user_actions]
  SCPS[SCP: restrict_non_singapore_regions]
  SCPE[SCP: enforce_encryption]
  SCPT[Org Target: Root/OU/Account]

  %% Runtime services
  ECSA[ECS Services]
  LBN[Lambda: notification]
  LBF[Lambda: fraud]
  SFN[State Machine: payment_workflow]

  %% Data/event/log resources
  CWAPP[CloudWatch Log Group: /sbcbank/env/app]
  CWVPC[CloudWatch Log Group: /aws/vpc/prefix/flow-logs]
  CWSFN[CloudWatch Log Group: /aws/states/prefix-payment-workflow]
  EVB[EventBridge Bus: main]
  SQST[SQS: transactions]
  SQSN[SQS: notifications]
  SQSM[SQS: manual_review]
  S3ST[S3: statements bucket]
  S3CT[S3: cloudtrail bucket]
  S3AT[S3: athena results bucket]
  S3CM[S3: compliance metrics bucket]
  RDS[(RDS PostgreSQL)]
  DDBL[DynamoDB: prefix-ledger]
  DDBF[DynamoDB: prefix-fraud-events]

  %% KMS keys
  KTR[KMS CMK: transaction_data_key]
  KPI[KMS CMK: pii_data_key]
  KLG[KMS CMK: logs_key]

  %% Trust relationships
  ECSP --> EEXR
  ECSP --> EACR
  ECSP --> ETRR
  ECSP --> ELRR
  ECSP --> ESRR
  ECSP --> ENRR
  LBDP --> LNXR
  LBDP --> LFXR
  SFP --> SFR
  VFLP --> VFLR
  HUMP --> ADM
  HUMP --> DVO
  HUMP --> AUD
  HUMP --> SUP

  %% Role attachment to runtimes
  EEXR --> ECSA
  EACR --> ECSA
  ETRR --> ECSA
  ELRR --> ECSA
  ESRR --> ECSA
  ENRR --> ECSA
  LNXR --> LBN
  LFXR --> LBF
  SFR --> SFN

  %% Optional identity center path
  IC -.-> PSA
  IC -.-> PSD
  IC -.-> PSU
  IC -.-> PSS

  %% Optional organizations path
  ORG -.-> SCPR
  ORG -.-> SCPS
  ORG -.-> SCPE
  SCPR -.-> SCPT
  SCPS -.-> SCPT
  SCPE -.-> SCPT

  %% Primary permission edges
  EEXR --> CWAPP

  EACR --> SQST

  ETRR --> SQST
  ETRR --> SQSN
  ETRR --> EVB

  ELRR --> DDBL

  ESRR --> DDBL
  ESRR --> S3ST

  ENRR --> SQSN

  LNXR --> S3ST
  LFXR --> DDBF

  SFR --> LBF
  SFR --> EVB
  SFR --> SQSM
  SFR --> CWSFN

  VFLR --> CWVPC

  %% KMS encryption usage
  KTR --> RDS
  KTR --> EACR
  KTR --> ETRR
  KTR --> ELRR
  KTR --> SFR
  KTR --> LFXR

  KPI --> S3ST
  KPI --> EACR
  KPI --> ESRR
  KPI --> LNXR

  KLG --> CWAPP
  KLG --> CWVPC
  KLG --> CWSFN
  KLG --> S3CT
  KLG --> S3AT
  KLG --> S3CM
```

## Source Mapping

- IAM roles and policies are defined in [terraform/main.tf](terraform/main.tf).
- Role outputs are exposed in [terraform/outputs.tf](terraform/outputs.tf).
- Optional Identity Center and Organizations/SCP resources are disabled by default for LocalStack and enabled via Terraform variables.

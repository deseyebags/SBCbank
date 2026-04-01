# SBCbank IAM Diagram

This diagram reflects the IAM roles, trust relationships, and primary permission paths currently defined in Terraform.

```mermaid
flowchart LR
  %% Trust principals
  ECSP[ecs-tasks.amazonaws.com]
  LBDP[lambda.amazonaws.com]
  SFP[states.amazonaws.com]
  VFLP[vpc-flow-logs.amazonaws.com]

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
  DDBL[DynamoDB: prefix-ledger]
  DDBF[DynamoDB: prefix-fraud-events]

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
```

## Source Mapping

- IAM roles and policies are defined in [terraform/main.tf](terraform/main.tf).
- Role outputs are exposed in [terraform/outputs.tf](terraform/outputs.tf).

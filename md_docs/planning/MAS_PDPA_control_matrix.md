# MAS and PDPA Control Matrix for SBCbank

## Scope

This matrix maps key Singapore regulatory obligations to your cloud-native banking architecture and current repository state.

- Regulatory baseline in scope: MAS TRM, MAS Outsourcing Guidelines, PDPA (including Data Breach Notification duties).
- Architecture reference: cloud-native target architecture in `bankinfo_concrete_overview.yaml`.
- Current implementation evidence: Terraform scaffolding in `terraform/main.tf` plus current runtime notes in `README.md`.

Note: This is an engineering control-mapping document, not legal advice.

## Regulations Most Relevant to This Project

1. MAS Technology Risk Management (TRM) Guidelines
2. MAS Outsourcing Guidelines (cloud service provider risk management)
3. PDPA obligations (including Protection, Retention, Transfer, and Breach Notification)

## Service-by-Service Control Mapping

Legend:
- `Implemented`: control is visibly implemented in repo assets.
- `Partial`: control exists but is incomplete, optional, or not fully enforced.
- `Gap`: control not yet implemented in current code/IaC.

| Component | MAS / PDPA requirement | Expected control for SBCbank | Current status | Evidence / notes |
|---|---|---|---|---|
| Organization / account governance | MAS TRM governance, MAS outsourcing oversight | Multi-account segregation (prod/dev/security/shared), SCP guardrails (deny root, region restriction, encryption enforcement) | Partial | Target defined in `bankinfo_concrete_overview.yaml`. SCP resources exist in `terraform/main.tf` but are optional and disabled unless `enable_organizations_governance=true`. |
| Data residency | MAS outsourcing + PDPA transfer controls | Operate in Singapore region by policy and prevent accidental deployment outside `ap-southeast-1` | Partial | Region default is `ap-southeast-1` in `terraform/variables.tf`, and optional SCP `restrict_non_singapore_regions` exists. Not hard-enforced unless SCP enabled and attached. |
| Edge/API entry (CloudFront/WAF/API Gateway/ALB) | MAS TRM secure perimeter controls | TLS 1.2+, WAF managed rules + rate limiting, strong auth at API layer, protected ingress | Partial | WAF managed rule set exists; ALB HTTPS policy supports TLS1.2+. No explicit WAF rate-limit rule found. API Gateway auth is scaffolded but end-to-end API integration is still TODO/scaffold. |
| Identity and access management | MAS TRM least privilege and strong auth | Least privilege IAM, no wildcard permissions where possible, short sessions, MFA for privileged users, role segregation | Partial | Human roles and service roles exist; several scoped policies are present. Some wildcard resources/actions still present for operational APIs, and MFA enforcement conditions are not explicitly encoded in IAM policies. |
| Key management and encryption | MAS TRM cryptographic controls, PDPA Protection Obligation | CMK-based encryption for transaction, PII, and logs; key rotation enabled; strict key grants | Implemented (core) / Partial (coverage) | KMS CMKs and aliases for transaction/PII/logs with rotation are defined. Some resources can fall back to AWS-managed/SSE-S3 depending on toggles and service capability. |
| Containerized microservices (ECS) | MAS TRM secure system architecture | Private subnets, SG segmentation, least-priv task roles, centralized logs | Partial | ECS services are private and use SG chaining ALB->ECS->DB/Redis. Logging to CloudWatch is configured. Workloads are still scaffold images and not production service artifacts. |
| Serverless functions (Lambda) | MAS TRM secure coding and runtime least privilege | Function-level IAM, encrypted artifacts, monitored invocation, event-driven isolation | Partial | Notification and fraud lambdas plus IAM and packaging are present. Scope is limited to initial functions and does not yet include full compliance lambda/ledger lambda implementation from target architecture. |
| Workflow orchestration (Step Functions) | MAS TRM transaction integrity and traceability | Deterministic workflow, auditable decision points, fraud decision branching, failure handling | Partial | Payment workflow and logging are implemented with approve/flag/block-like branches. Business integrations are still mostly pass/task scaffolding rather than full service transactions. |
| Messaging and events (SQS/EventBridge) | MAS TRM resilience and controlled async processing | Encrypted queues, DLQs, secure transport deny, event bus with controlled producers/consumers | Partial | Queues, DLQs, secure transport deny policies, and event bus/rules are present. Full producer/consumer contract alignment to merged spec events remains incomplete. |
| Data stores (RDS/Redis/DynamoDB/S3) | MAS TRM data security, PDPA Protection/Retention | Encryption at rest/in transit, private network access, immutability for ledger/logs, retention controls | Partial | RDS encryption + private SG path exists. Redis encryption-in-transit/at-rest is required in spec but not fully configured in current cluster resource. S3 encryption/public-block/versioning are present. S3 Object Lock for logs required by spec is not implemented in current Terraform buckets. |
| Audit logging and monitoring | MAS TRM auditability, PDPA accountability | CloudTrail, VPC flow logs, app logs, log integrity validation, centralized retention and alerting | Partial | CloudTrail with log file validation and log groups exist; VPC flow logs and alarms exist. ALB access logs and full centralized security logging account pattern are not fully implemented. |
| Threat detection and governance | MAS TRM continuous security monitoring | GuardDuty, Security Hub, AWS Config, IAM Access Analyzer with alerts/remediation | Gap | Required in target spec but no corresponding Terraform resources found in current implementation. |
| Compliance analytics dashboard | MAS governance reporting, PDPA accountability | Security + operational compliance KPIs with trend visibility and alerts | Partial | Athena/Glue/CloudWatch compliance dashboard resources are present, focused mainly on operational metrics; not yet covering full control evidence metrics (e.g., IAM policy violations, public exposure, MFA rate). |
| PDPA consent/purpose/notification | PDPA Consent, Purpose Limitation, Notification obligations | Service-level consent records, purpose tags, privacy notice linkage, lawful-use checks | Gap | No clear domain-level consent/purpose enforcement model or evidence table in current backend/runtime assets. |
| PDPA access/correction rights | PDPA Access and Correction obligations | API and operational workflow for data access/correction requests and response SLA tracking | Gap | No dedicated DSR (data subject request) workflow/components found in current implementation. |
| PDPA retention and disposal | PDPA Retention Limitation obligation | Data retention schedule per dataset, legal hold handling, purge/anonymization jobs | Gap | Some infra retention exists (e.g., logs, queue retention), but no end-to-end retention policy automation for PII/business records is defined. |
| PDPA breach management | PDPA Data Breach Notification | Detection-to-assessment workflow, severity thresholds, 3-day notification clock, evidence logs | Gap | Security telemetry exists partially, but no explicit breach playbook automation or notification workflow found in repo. |
| Outsourcing assurance (AWS/CSP) | MAS Outsourcing Guidelines | Due diligence records, contractual controls, right-to-audit evidence, concentration/subcontractor risk management | Gap (process) | Mostly governance/process controls; not represented as code in repo today. Should be tracked in policy/third-party risk register artifacts. |

## Prioritized Gap List

### Priority 0 (must close before production/regulatory readiness)

1. Enforce region and encryption guardrails in Organizations at runtime
- Turn on and attach SCPs in actual org targets.
- Validate break-glass exceptions and global-service allowlist.

2. Implement missing security governance services
- Add and baseline AWS Config, Security Hub, GuardDuty, IAM Access Analyzer.
- Route findings into ticketing and compliance dashboard.

3. Complete logging integrity and centralization controls
- Add immutable log controls (Object Lock where required) and ALB access logs.
- Centralize security logs to dedicated logging account/buckets.

4. Close PDPA operational obligations in application layer
- Implement consent/purpose data model and API checks.
- Implement DSR access/correction workflow and tracking.
- Implement breach workflow with assessment and notification timer controls.

### Priority 1 (high-impact hardening)

1. Enforce MFA/conditional access for privileged IAM role assumption.
2. Remove or reduce wildcard IAM permissions where feasible.
3. Upgrade Redis deployment mode/config to meet encryption and HA intent.
4. Expand compliance dashboard to include security control KPIs from Security Hub/Config/Access Analyzer.

### Priority 2 (evidence and assurance maturity)

1. Create MAS outsourcing evidence pack (due diligence, exit plan, audit rights, subcontractor transparency).
2. Add control-to-test mapping (automated policy checks + periodic control attestations).
3. Add data lifecycle register per data class (transaction, PII, logs, fraud artifacts).

## Suggested Backlog Tickets (ready to create)

1. `SEC-001` Enable and attach Organizations SCPs for region and encryption enforcement.
2. `SEC-002` Provision GuardDuty, Security Hub, AWS Config, IAM Access Analyzer and wire alerting.
3. `SEC-003` Enable ALB access logging and immutable retention strategy for security logs.
4. `IAM-001` Add MFA-required role assumption conditions for privileged human roles.
5. `IAM-002` Review and reduce wildcard IAM statements in Step Functions and shared policies.
6. `DATA-001` Implement PDPA consent and purpose-limitation schema plus policy checks in APIs.
7. `DATA-002` Implement PDPA data access/correction request workflow with audit trail.
8. `IR-001` Implement PDPA breach-notification runbook automation and evidence timeline capture.
9. `OBS-001` Extend compliance dashboard with security posture KPIs from governance services.

## Evidence Anchors in Current Repo

- Compliance frameworks and baseline objectives: `bankinfo_concrete_overview.yaml`
- Cloud-native control requirements and security objectives: `bankinfo_concrete_overview.yaml`
- Terraform control implementations and stubs: `terraform/main.tf`
- Security/governance toggles and defaults: `terraform/variables.tf`
- Current active runtime context (Docker-first, infra assets marked legacy): `README.md`

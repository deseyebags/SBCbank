# Backend Implementation Plan for SBCbank

## Overview

This plan outlines the backend implementation strategy for the SBCbank project, based on the architecture and requirements defined in the Terraform scripts and project documentation. It is intended as a handoff for another model or developer to implement the backend code, ensuring adherence to best practices, compliance, and maintainability.

---

## 1. Microservice Architecture

- **Services:**
  - `account_service`
  - `payment_service`
  - `ledger_service`
  - `statement_service`
- **Deployment:** ECS Fargate, Singapore region (`ap-southeast-1`)
- **API Gateway:** AWS API Gateway v2 (HTTP API) → ALB → ECS
- **Async Processing:** SQS for transactions and notifications

---

## 2. Service Design Principles

- **Separation of Concerns:** Each service handles a distinct domain (accounts, payments, ledger, statements)
- **Statelessness:** Services should be stateless; use RDS PostgreSQL and Redis for persistence and caching
- **API Contracts:** Define OpenAPI 3.0+ specs for each service
- **Error Handling:** Standardized error responses, logging to CloudWatch
- **Input Validation:** Validate all incoming requests (schema, type, business rules)
- **Security:**
  - Use IAM roles with least privilege
  - No hardcoded secrets; use environment variables or AWS Secrets Manager
  - Network isolation: databases in private subnets, no public access
  - Encryption at rest and in transit

---

## 3. Workflow Orchestration

- **Step Functions:**
  - Orchestrate payment workflow: account validation → transaction creation → fraud check → approve/flag/block
  - Branching logic for manual review (SQS queue)
- **EventBridge:**
  - Producers/consumers for workflow events
  - Connect to SQS for manual review and notifications

---

## 4. Data Layer

- **RDS PostgreSQL 16:**
  - Multi-AZ in prod, single-AZ in dev/staging
  - Strict schema design, normalization, indexing
  - Deletion protection in prod
- **ElastiCache Redis 7:**
  - Session caching, idempotency, rate limiting

---

## 5. Observability & Logging

- **CloudWatch Logs:**
  - Centralized at `/sbcbank/{environment}/app`
  - Structured logging (JSON)
  - Log API requests, errors, workflow events

---

## 6. Compliance & Best Practices

- **MAS TRM, Outsourcing, PDPA:**
  - Singapore region only
  - Encryption everywhere
  - Resource naming: `{project_name}-{environment}-{resource}`
- **Terraform Patterns:**
  - Use outputs for endpoints, mark sensitive outputs
  - Security groups: ALB → ECS → RDS/Redis
  - Conditional logic for environment-specific resources

---

## 7. Development & Testing

- **LocalStack:**
  - Mock AWS services for local development
  - Use test containers for integration tests
- **CI/CD:**
  - Automated tests for API contracts, workflows, and data integrity
  - Linting, static analysis, and security scans

---

## 8. Handoff Requirements

- **Documentation:**
  - API specs (OpenAPI)
  - Service diagrams
  - Workflow charts
- **Code Structure:**
  - Controllers, services, models, repositories
  - Configuration files for environment management
- **Testing:**
  - Unit, integration, and workflow tests

---

## 9. Implementation Checklist

- [ ] Define OpenAPI specs for all services
- [ ] Implement service skeletons with proper separation
- [ ] Integrate with AWS resources as provisioned by Terraform
- [ ] Set up logging, error handling, and validation
- [ ] Ensure compliance and security controls
- [ ] Provide documentation and test cases

---

## References

- [bankinfo_concrete_overview.yaml](bankinfo_concrete_overview.yaml)
- [terraform/main.tf](terraform/main.tf)
- [README.md](README.md)

---

**This plan is intended for backend implementation handoff. Follow all best practices and compliance requirements as outlined.**

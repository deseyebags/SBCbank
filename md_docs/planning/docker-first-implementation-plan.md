# SBCbank Docker-First Implementation Plan

## Scope Reset
- Runtime target is local Docker and Docker Compose only.
- Terraform/AWS/LocalStack are no longer required for daily development.
- Backend implementation target is FastAPI services with orchestration handled by a dedicated internal service.
- Frontend implementation target is React with shadcn/ui.
- Fraud detection and manual-review workflow are out of scope for this cycle.

## 1) User Stories and Use Cases

### Customer-Facing User Stories
1. As a user, I can create a bank account with name and email.
2. As a user, I can view all accounts and account details.
3. As a user, I can credit and debit account balances.
4. As a user, I can initiate a P2P payment.
5. As a user, I can view payment status and payment history.
6. As a user, I can view ledger entries for transaction transparency.
7. As a user, I can generate and view statements by period.

### Internal and Developer Use Cases
1. As a developer, I can run the full stack locally with one compose command.
2. As a developer, I can reseed mock data quickly for demos and tests.
3. As an operator, I can check health endpoints for each service.
4. As an operator, I can inspect orchestration execution state for failed workflows.

### Out-of-Scope Use Cases (Current Cycle)
1. Real-time fraud scoring and fraud risk decisions.
2. Manual-review queue and compliance dashboards.
3. AWS-managed orchestration/eventing auth layers (Step Functions/EventBridge/Cognito).

## 2) Services Required

### Domain Services
1. account-service:
- Owns account records and balance operations.
- APIs: list/create/get, debit, credit.

2. payment-service:
- Owns payment records and status lifecycle.
- Creates payment intents and delegates workflow execution to orchestrator-service.

3. ledger-service:
- Owns append-style ledger records for payment audit trail.

4. statement-service:
- Owns statement records and retrieval APIs.

### Orchestration Layer
5. orchestrator-service (new):
- Central workflow coordinator for P2P payment execution.
- Validates payer and recipient accounts.
- Executes debit then credit with compensation on partial failure.
- Writes ledger record on successful completion.
- Persists orchestration execution state in PostgreSQL.
- Internal API only for MVP.

### Platform Services
6. postgres:
- Primary data store for account, payment, ledger, statement, and orchestration state.

7. redis (optional in MVP):
- Reserved for caching/idempotency/session-like patterns.

8. frontend (React + shadcn):
- Consumes domain APIs through reverse proxy.

9. reverse-proxy:
- Single ingress for browser and API path routing.

## 3) Routing and Network Plan

### Network Topology
- All services run in one Docker bridge network.
- Service-to-service communication uses Docker DNS service names.
- No service should use localhost for cross-container calls.

### External Entry Points
- Frontend is exposed to local browser.
- Reverse-proxy exposes API paths for frontend consumption.

### API Routing Strategy
- /api/accounts -> account-service
- /api/payments -> payment-service
- /api/ledger -> ledger-service
- /api/statements -> statement-service
- Orchestrator endpoints remain internal and are not proxied publicly in MVP.

### Internal Workflow Routing
1. Client calls payment-service to initiate P2P payment.
2. payment-service creates PENDING payment and calls orchestrator-service.
3. orchestrator-service calls account-service for validation/debit/credit.
4. orchestrator-service calls ledger-service to append ledger entry.
5. orchestrator-service returns workflow result to payment-service.
6. payment-service sets final payment status and returns response to caller.

## Data and State Plan

### New Orchestration State Table
- Table: orchestration_executions
- Fields:
  - execution_id
  - payment_id
  - workflow_type
  - status
  - retry_count
  - error_message
  - created_at
  - updated_at
  - completed_at

### Payment Model Evolution
- Add recipient_account_id
- Add execution_id for orchestration correlation

## Delivery Phases
1. Phase 1: Add orchestration service and payment delegation path.
2. Phase 2: Remove AWS-runtime dependencies from backend services.
3. Phase 3: Wire compose and runtime env for orchestration.
4. Phase 4: Add reverse proxy and frontend integration.
5. Phase 5: Update documentation to Docker-first runbook.
6. Phase 6: Harden tests and idempotency/retry behavior.

## Verification Checklist
1. docker compose starts all backend services healthy.
2. P2P payment path succeeds end-to-end without AWS clients.
3. Failed orchestration path marks payment as FAILED.
4. Ledger entries are written on successful P2P.
5. No Terraform or LocalStack prerequisites in local runbook.

## Initial Implementation Status
- Added orchestration model and orchestrator-service skeleton.
- Refactored payment-service P2P endpoint to delegate orchestration.
- Removed AWS-specific runtime clients from payment/ledger/statement services.
- Updated compose and env example for orchestration wiring.
- Updated payment tests to validate orchestrator delegation.

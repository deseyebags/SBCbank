# scbbank Backend

This backend runs as local Dockerized FastAPI microservices with PostgreSQL and Redis.

Active local development does not require Terraform, AWS, or LocalStack.

Statement generation now emits RabbitMQ messages that are consumed by `notification-service` to send monthly statement emails (mocked unless SMTP is configured).

Authentication and authorization are enforced at service endpoints using bearer tokens.

## Quickstart

1. Copy runtime env template:
   ```powershell
   Copy-Item .env.runtime.example .env.runtime
   ```
2. Start all backend services:
   ```powershell
   docker compose up --build -d
   ```
3. Stop services:
   ```powershell
   docker compose down
   ```

## Services

- Account: `http://localhost:8001/accounts`
- Auth (Account service): `http://localhost:8001/auth/*`
- Payment: `http://localhost:8002/payments`
- Ledger: `http://localhost:8003/ledger`
- Statement: `http://localhost:8004/statements`
- Orchestrator (internal): `http://localhost:8005/internal/orchestrations/payments`
- Notification: `http://localhost:8006/health`
- RabbitMQ management UI: `http://localhost:15672` (`scbbank` / `scbbank`)

## Authentication

- Admin login endpoint: `POST /auth/login/admin`
- User login endpoint: `POST /auth/login/user`
- Session check endpoint: `GET /auth/me`

Default local admin credentials:

- Username: `admin`
- Password: `admin123`

User login requires both:

- `account_id`
- Matching account `email`

Role permissions:

- `admin`: full access to account/payment/ledger/statement operations.
- `user`: restricted to account-scoped payments and statements.
- Internal service calls use `X-Internal-Token` for orchestrator-to-service authorization.

## Compose Files

- `docker-compose.yml`: active local development stack.
- `docker-compose.localstack.yml`: compatibility stack retained during migration.

## Architecture Notes

- `payment-service` creates payment intents and delegates P2P workflow execution to `orchestrator-service`.
- `orchestrator-service` coordinates account validation, debit/credit operations, and ledger writes.
- Workflow execution state is persisted in `orchestration_executions`.

## Tests

Run backend tests from this directory:

```powershell
pytest
```

## Reference Plans

- Current implementation plan: `../docker-first-implementation-plan.md`
- Prior backend plan: `../backend-implementation-plan.md`

## Directory Structure

- `account_service/` — account APIs
- `payment_service/` — payment APIs and orchestration delegation
- `orchestrator_service/` — payment workflow coordination
- `ledger_service/` — ledger record APIs
- `statement_service/` — statement APIs
- `models/` — shared SQLAlchemy models
- `config/` — shared database/base configuration
- `tests/` — service-level tests

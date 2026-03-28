# SBCbank

Local-first banking microservice project for SMU IS458 (Team 2).

The active development path is Docker and Docker Compose only. Local runtime no longer depends on Terraform, AWS, or LocalStack.

---

## Table of Contents

1. [Current Runtime Architecture](#current-runtime-architecture)
2. [Prerequisites](#prerequisites)
3. [Quickstart](#quickstart)
4. [Service Endpoints](#service-endpoints)
5. [Repository Notes](#repository-notes)
6. [Legacy Infrastructure Assets](#legacy-infrastructure-assets)

---

## Current Runtime Architecture

| Layer | Technology |
|---|---|
| Frontend | React + shadcn (in progress) |
| Backend APIs | FastAPI microservices |
| Workflow Coordination | Internal orchestration service |
| Database | PostgreSQL 16 (Docker container) |
| Cache | Redis 7 (Docker container) |
| Networking | Docker bridge network + container DNS |

The frontend now uses route-based role experiences:

- `/login`: authentication screen
- `/admin`: admin operations workspace
- `/app`: user workspace

The orchestration service now coordinates payment workflow execution for local development.

---

## Prerequisites

- Docker Desktop (or Docker Engine + Compose plugin)
- Git

---

## Quickstart

1. Clone repository:

```bash
git clone https://github.com/deseyebags/SBCbank.git
cd SBCbank
```

2. Prepare backend runtime environment:

```bash
cp backend/.env.runtime.example backend/.env.runtime
```

Windows PowerShell alternative:

```powershell
Copy-Item backend\.env.runtime.example backend\.env.runtime
```

3. Start backend stack:

```bash
cd backend
docker compose up --build -d
```

4. Stop backend stack:

```bash
cd backend
docker compose down
```

5. Start frontend development server:

```bash
cd frontend
npm install
npm run dev
```

6. Sign in through the frontend at `http://localhost:5173/login`:

- Admin: `admin` / `admin123`
- User: account ID + matching account email

---

## Service Endpoints

- Account service: http://localhost:8001/accounts
- Auth endpoints: http://localhost:8001/auth/login/admin and http://localhost:8001/auth/login/user
- Payment service: http://localhost:8002/payments
- Ledger service: http://localhost:8003/ledger
- Statement service: http://localhost:8004/statements
- Orchestrator service (internal API): http://localhost:8005/internal/orchestrations/payments
- Notification service: http://localhost:8006/health
- RabbitMQ management UI: http://localhost:15672 (sbcbank / sbcbank)

---

## Repository Notes

- Current execution plan is tracked in `docker-first-implementation-plan.md`.
- Payment orchestration is synchronous for MVP and internal-only.
- Fraud detection and manual-review workflow are intentionally out of scope in this cycle.

---

## Legacy Infrastructure Assets

Terraform and AWS-oriented files remain in the repository for historical/reference use, but are not part of the active local run path.

### Terraform Commands (Legacy)

For local Terraform development with LocalStack:

```bash
cd terraform
terraform init -reconfigure
terraform validate
terraform plan -var-file="localstack.tfvars" -var="db_password=localpassword"
terraform apply -var-file="localstack.tfvars" -var="db_password=localpassword"
```

To clean up LocalStack-provisioned Terraform resources:

```bash
cd terraform
terraform destroy -var-file="localstack.tfvars" -var="db_password=localpassword"
```

For AWS-backed deployment (non-LocalStack), use environment-specific values and credentials:

```bash
cd terraform
terraform init
terraform apply -var="environment=dev" -var="db_password=<strong-password>"
```


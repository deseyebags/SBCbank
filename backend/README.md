# SBCbank Backend

This backend implements microservices for SBCbank using FastAPI, PostgreSQL, Redis, and integrates with AWS resources provisioned by Terraform.

## Quickstart

1. **Install Python 3.11+ and pip**
2. **Create a virtual environment:**
   ```bash
   python -m venv .venv
   source .venv/bin/activate  # On Windows: .venv\Scripts\activate
   ```
3. **Install dependencies:**
   ```bash
   pip install -r requirements.txt
   ```
4. **Configure environment variables:**
   - Copy `.env.example` to `.env` and update values as needed
5. **Run the app locally:**
   ```bash
   uvicorn main:app --reload
   ```
6. **Local AWS emulation:**
   - Start LocalStack: `./setup-localstack.sh`
   - Ensure Terraform resources are provisioned: `cd terraform && terraform apply -var-file=localstack.tfvars`

## Containerized Microservice Deployment (LocalStack + Terraform)

This repository includes resources to build all microservice images and run them against Terraform-provisioned LocalStack infrastructure.

1. From the repository root, run:

   ```powershell
   .\scripts\deploy-localstack-microservices.ps1
   ```

2. The script will:
   - apply Terraform using `terraform/localstack.tfvars`
   - read Terraform outputs
   - generate `backend/.env.runtime` with resource endpoints and AWS settings
   - start PostgreSQL and Redis containers
   - build and run all microservice containers via `backend/docker-compose.localstack.yml`

3. Service endpoints:
   - Account: `http://localhost:8001/accounts`
   - Payment: `http://localhost:8002/payments`
   - Ledger: `http://localhost:8003/ledger`
   - Statement: `http://localhost:8004/statements`

4. To stop containers:

   ```powershell
   cd backend
   docker compose -f docker-compose.localstack.yml down
   ```

5. To fully tear down services + Terraform resources:

   ```powershell
   .\scripts\teardown-localstack-microservices.ps1
   ```

6. To rebuild from scratch:
   ```powershell
   cd backend
   docker compose -f docker-compose.localstack.yml down
   docker compose -f docker-compose.localstack.yml build --no-cache
   docker compose -f docker-compose.localstack.yml up -d
   ```

## Directory Structure

- `main.py` — FastAPI entrypoint
- `services/` — Microservice modules
- `models/` — Database models
- `config/` — Configuration and environment management
- `tests/` — Unit and integration tests

## Integration

- Ensure Terraform scripts are applied before running the backend for proper AWS resource integration.
- Use LocalStack for local development and testing.

## Compliance

- Follows MAS TRM, PDPA, and best practices outlined in backend-implementation-plan.md

---

For detailed implementation plan, see ../backend-implementation-plan.md

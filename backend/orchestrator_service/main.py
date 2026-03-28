from datetime import datetime
import os
from contextlib import asynccontextmanager

from fastapi import Depends, FastAPI
from pydantic import BaseModel
import requests
from sqlalchemy.orm import Session

from config.auth import require_internal_service
from config.base import Base
from config.database import SessionLocal, engine
from models.orchestration import OrchestrationExecution


ACCOUNT_SERVICE_URL = os.getenv("ACCOUNT_SERVICE_URL", "http://account-service:8000")
LEDGER_SERVICE_URL = os.getenv("LEDGER_SERVICE_URL", "http://ledger-service:8000")
REQUEST_TIMEOUT_SECONDS = float(os.getenv("REQUEST_TIMEOUT_SECONDS", "5"))
ORCHESTRATOR_MAX_RETRIES = int(os.getenv("ORCHESTRATOR_MAX_RETRIES", "1"))
INTERNAL_SERVICE_TOKEN = os.getenv("INTERNAL_SERVICE_TOKEN", "scbbank-internal-token")
INTERNAL_SERVICE_HEADERS = {"X-Internal-Token": INTERNAL_SERVICE_TOKEN}


@asynccontextmanager
async def lifespan(_: FastAPI):
    Base.metadata.create_all(bind=engine)
    yield


app = FastAPI(lifespan=lifespan)


class PaymentOrchestrationRequest(BaseModel):
    execution_id: str
    payment_id: int
    payer_account_id: int
    recipient_account_id: int
    amount: float


def get_db() -> Session:
    return SessionLocal()


def request_with_retry(method: str, url: str, **kwargs):
    attempts = ORCHESTRATOR_MAX_RETRIES + 1
    last_exception = None

    for _ in range(attempts):
        try:
            response = requests.request(method, url, timeout=REQUEST_TIMEOUT_SECONDS, **kwargs)
            response.raise_for_status()
            return response
        except requests.RequestException as exc:
            last_exception = exc

    raise RuntimeError(f"Service call failed after {attempts} attempts: {url}") from last_exception


@app.get("/health")
def health():
    return {"status": "ok"}


@app.post("/internal/orchestrations/payments")
def orchestrate_payment(
    payload: PaymentOrchestrationRequest,
    _: None = Depends(require_internal_service),
):
    execution_id = payload.execution_id
    payment_id = payload.payment_id
    payer_account_id = payload.payer_account_id
    recipient_account_id = payload.recipient_account_id
    amount = payload.amount

    db = get_db()
    try:
        existing = db.query(OrchestrationExecution).filter(
            OrchestrationExecution.execution_id == execution_id
        ).first()
        if existing:
            return {
                "execution_id": existing.execution_id,
                "workflow_status": existing.status,
                "payment_status": "SUCCESS" if existing.status == "COMPLETED" else "FAILED",
            }

        execution = OrchestrationExecution(
            execution_id=execution_id,
            payment_id=payment_id,
            workflow_type="P2P_PAYMENT",
            status="RUNNING",
        )
        db.add(execution)
        db.commit()

        try:
            request_with_retry(
                "GET",
                f"{ACCOUNT_SERVICE_URL}/accounts/{payer_account_id}",
                headers=INTERNAL_SERVICE_HEADERS,
            )
            request_with_retry(
                "GET",
                f"{ACCOUNT_SERVICE_URL}/accounts/{recipient_account_id}",
                headers=INTERNAL_SERVICE_HEADERS,
            )

            request_with_retry(
                "POST",
                f"{ACCOUNT_SERVICE_URL}/accounts/debit",
                params={"account_id": payer_account_id, "amount": amount},
                headers=INTERNAL_SERVICE_HEADERS,
            )

            try:
                request_with_retry(
                    "POST",
                    f"{ACCOUNT_SERVICE_URL}/accounts/credit",
                    params={"account_id": recipient_account_id, "amount": amount},
                    headers=INTERNAL_SERVICE_HEADERS,
                )
            except Exception as exc:
                # Compensating action for partial failure after debit succeeds.
                request_with_retry(
                    "POST",
                    f"{ACCOUNT_SERVICE_URL}/accounts/credit",
                    params={"account_id": payer_account_id, "amount": amount},
                    headers=INTERNAL_SERVICE_HEADERS,
                )
                raise RuntimeError("Credit to recipient failed; payer was refunded") from exc

            ledger_description = (
                f"P2P payment {payment_id}: {payer_account_id} -> {recipient_account_id}"
            )
            request_with_retry(
                "POST",
                f"{LEDGER_SERVICE_URL}/ledger",
                params={"description": ledger_description, "amount": amount},
                headers=INTERNAL_SERVICE_HEADERS,
            )

            execution.status = "COMPLETED"
            execution.completed_at = datetime.utcnow()
            execution.updated_at = datetime.utcnow()
            db.commit()

            return {
                "execution_id": execution_id,
                "workflow_status": "COMPLETED",
                "payment_status": "SUCCESS",
            }
        except (RuntimeError, ValueError, TypeError, requests.RequestException) as exc:
            execution.status = "FAILED"
            execution.error_message = str(exc)
            execution.completed_at = datetime.utcnow()
            execution.updated_at = datetime.utcnow()
            db.commit()

            return {
                "execution_id": execution_id,
                "workflow_status": "FAILED",
                "payment_status": "FAILED",
                "error": str(exc),
            }
    finally:
        db.close()

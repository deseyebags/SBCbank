from contextlib import asynccontextmanager
from datetime import UTC, datetime
import os
import uuid

from fastapi import FastAPI, Depends, HTTPException
import requests
from sqlalchemy import or_
from sqlalchemy.orm import Session
from config.auth import AuthContext, ensure_account_access, get_auth_context, require_roles
from config.database import SessionLocal, engine
from config.base import Base
import models.account  # noqa: F401
from models.payment import Payment

@asynccontextmanager
async def lifespan(_: FastAPI):
    Base.metadata.create_all(bind=engine)
    yield


app = FastAPI(lifespan=lifespan)

ORCHESTRATOR_SERVICE_URL = os.getenv("ORCHESTRATOR_SERVICE_URL", "http://orchestrator-service:8000")
REQUEST_TIMEOUT_SECONDS = float(os.getenv("REQUEST_TIMEOUT_SECONDS", "5"))
INTERNAL_SERVICE_TOKEN = os.getenv("INTERNAL_SERVICE_TOKEN", "scbbank-internal-token")

def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()

@app.get("/health")
def health():
    return {"status": "ok"}

@app.get("/payments")
def list_payments(
    auth: AuthContext = Depends(get_auth_context),
    db: Session = Depends(get_db),
):
    query = db.query(Payment)
    if auth.role == "user":
        if auth.account_id is None:
            raise HTTPException(status_code=403, detail="Account access denied")

        query = query.filter(
            or_(
                Payment.account_id == auth.account_id,
                Payment.recipient_account_id == auth.account_id,
            )
        )

    payments = query.all()
    return {"payments": payments}

@app.post("/payments")
def create_payment(
    account_id: int,
    amount: float,
    status: str,
    _: AuthContext = Depends(require_roles("admin")),
    db: Session = Depends(get_db),
):
    payment = Payment(
        account_id=account_id,
        amount=amount,
        status=status,
        created_at=datetime.now(UTC).replace(tzinfo=None),
    )
    db.add(payment)
    db.commit()
    db.refresh(payment)
    return payment

@app.get("/payments/{payment_id}")
def get_payment(
    payment_id: int,
    auth: AuthContext = Depends(get_auth_context),
    db: Session = Depends(get_db),
):
    payment = db.query(Payment).filter(Payment.id == payment_id).first()
    if not payment:
        raise HTTPException(status_code=404, detail="Payment not found")

    if auth.role == "user":
        allowed_account_ids = {
            payment.account_id,
            payment.recipient_account_id,
        }
        if auth.account_id not in allowed_account_ids:
            raise HTTPException(status_code=403, detail="Payment access denied")

    return payment

@app.post("/payments/p2p")
def initiate_p2p_payment(
    account_id: int,
    recipient_id: int,
    amount: float,
    auth: AuthContext = Depends(get_auth_context),
    db: Session = Depends(get_db),
):
    ensure_account_access(auth, account_id)

    payment = Payment(
        account_id=account_id,
        recipient_account_id=recipient_id,
        amount=amount,
        status="PENDING",
        execution_id=str(uuid.uuid4()),
        created_at=datetime.now(UTC).replace(tzinfo=None),
    )
    db.add(payment)
    db.commit()
    db.refresh(payment)

    payload = {
        "execution_id": payment.execution_id,
        "payment_id": payment.id,
        "payer_account_id": account_id,
        "recipient_account_id": recipient_id,
        "amount": amount,
    }

    try:
        response = requests.post(
            f"{ORCHESTRATOR_SERVICE_URL}/internal/orchestrations/payments",
            json=payload,
            headers={"X-Internal-Token": INTERNAL_SERVICE_TOKEN},
            timeout=REQUEST_TIMEOUT_SECONDS,
        )
        response.raise_for_status()
        orchestrator_result = response.json()
    except requests.RequestException as exc:
        payment.status = "FAILED"
        db.commit()
        raise HTTPException(status_code=502, detail=f"Unable to reach orchestration service: {exc}") from exc

    payment.status = orchestrator_result.get("payment_status", "FAILED")
    db.commit()
    db.refresh(payment)

    return {
        "payment_id": payment.id,
        "execution_id": payment.execution_id,
        "status": payment.status,
        "workflow_status": orchestrator_result.get("workflow_status", "UNKNOWN"),
    }

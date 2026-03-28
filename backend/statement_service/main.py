from contextlib import asynccontextmanager
from datetime import UTC, datetime
import json
import os
from typing import Any

from fastapi import FastAPI, Depends, HTTPException
import pika
from sqlalchemy import and_, or_
from sqlalchemy.orm import Session
from config.auth import AuthContext, ensure_account_access, get_auth_context
from config.database import SessionLocal, engine
from config.base import Base
from models.account import Account
from models.payment import Payment
from models.statement import Statement

RABBITMQ_HOST = os.getenv("RABBITMQ_HOST", "rabbitmq")
RABBITMQ_PORT = int(os.getenv("RABBITMQ_PORT", "5672"))
RABBITMQ_USER = os.getenv("RABBITMQ_USER", "scbbank")
RABBITMQ_PASSWORD = os.getenv("RABBITMQ_PASSWORD", "scbbank")
STATEMENT_NOTIFICATION_QUEUE = os.getenv("STATEMENT_NOTIFICATION_QUEUE", "statement_notifications")

@asynccontextmanager
async def lifespan(_: FastAPI):
    Base.metadata.create_all(bind=engine)
    yield


app = FastAPI(lifespan=lifespan)

def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()


def parse_period_bounds(period: str) -> tuple[datetime, datetime]:
    try:
        start = datetime.strptime(period, "%Y-%m")
    except ValueError as exc:
        raise HTTPException(status_code=400, detail="Period must be in YYYY-MM format") from exc

    if start.month == 12:
        end = datetime(start.year + 1, 1, 1)
    else:
        end = datetime(start.year, start.month + 1, 1)

    return start, end


def build_statement_transactions(account_id: int, payments: list[Payment]) -> tuple[list[dict[str, Any]], float, float]:
    transactions: list[dict[str, Any]] = []
    total_debits = 0.0
    total_credits = 0.0

    for payment in payments:
        is_debit = payment.account_id == account_id
        amount = float(payment.amount)

        if is_debit:
            total_debits += amount
            direction = "DEBIT"
            counterparty_account_id = payment.recipient_account_id
        else:
            total_credits += amount
            direction = "CREDIT"
            counterparty_account_id = payment.account_id

        transactions.append(
            {
                "payment_id": payment.id,
                "direction": direction,
                "amount": amount,
                "counterparty_account_id": counterparty_account_id,
                "status": payment.status,
                "created_at": payment.created_at.isoformat() if payment.created_at else None,
            }
        )

    return transactions, total_debits, total_credits


def publish_statement_notification(payload: dict[str, Any]) -> None:
    credentials = pika.PlainCredentials(RABBITMQ_USER, RABBITMQ_PASSWORD)
    connection = pika.BlockingConnection(
        pika.ConnectionParameters(
            host=RABBITMQ_HOST,
            port=RABBITMQ_PORT,
            credentials=credentials,
        )
    )

    try:
        channel = connection.channel()
        channel.queue_declare(queue=STATEMENT_NOTIFICATION_QUEUE, durable=True)
        channel.basic_publish(
            exchange="",
            routing_key=STATEMENT_NOTIFICATION_QUEUE,
            body=json.dumps(payload).encode("utf-8"),
            properties=pika.BasicProperties(
                delivery_mode=2,
                content_type="application/json",
            ),
        )
    finally:
        connection.close()

@app.get("/health")
def health():
    return {"status": "ok"}

@app.get("/statements")
def list_statements(
    auth: AuthContext = Depends(get_auth_context),
    db: Session = Depends(get_db),
):
    query = db.query(Statement)
    if auth.role == "user":
        if auth.account_id is None:
            raise HTTPException(status_code=403, detail="Account access denied")
        query = query.filter(Statement.account_id == auth.account_id)

    statements = query.all()
    return {"statements": statements}

@app.post("/statements")
def create_statement(
    account_id: int,
    period: str,
    auth: AuthContext = Depends(get_auth_context),
    db: Session = Depends(get_db),
):
    ensure_account_access(auth, account_id)

    period_start, period_end = parse_period_bounds(period)

    account = db.query(Account).filter(Account.id == account_id).first()
    if not account:
        raise HTTPException(status_code=404, detail="Account not found")

    statement = Statement(account_id=account_id, period=period)
    db.add(statement)
    db.flush()

    payments = (
        db.query(Payment)
        .filter(
            and_(
                or_(
                    Payment.account_id == account_id,
                    Payment.recipient_account_id == account_id,
                ),
                Payment.created_at >= period_start,
                Payment.created_at < period_end,
            )
        )
        .order_by(Payment.created_at.asc(), Payment.id.asc())
        .all()
    )

    transactions, total_debits, total_credits = build_statement_transactions(account_id, payments)

    notification_payload = {
        "type": "statement.generated",
        "recipient": {
            "account_id": account.id,
            "name": account.name,
            "email": account.email,
        },
        "statement": {
            "statement_id": statement.id,
            "period": period,
            "generated_at": datetime.now(UTC).isoformat(),
        },
        "summary": {
            "transaction_count": len(transactions),
            "total_debits": round(total_debits, 2),
            "total_credits": round(total_credits, 2),
            "net_total": round(total_credits - total_debits, 2),
        },
        "transactions": transactions,
    }

    try:
        publish_statement_notification(notification_payload)
    except Exception as exc:
        db.rollback()
        raise HTTPException(status_code=502, detail=f"Failed to emit statement notification: {exc}") from exc

    db.commit()
    db.refresh(statement)
    return statement

@app.get("/statements/{statement_id}")
def get_statement(
    statement_id: int,
    auth: AuthContext = Depends(get_auth_context),
    db: Session = Depends(get_db),
):
    statement = db.query(Statement).filter(Statement.id == statement_id).first()
    if not statement:
        raise HTTPException(status_code=404, detail="Statement not found")

    ensure_account_access(auth, statement.account_id)
    return statement

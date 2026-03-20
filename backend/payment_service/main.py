from contextlib import asynccontextmanager

from fastapi import FastAPI, Depends, HTTPException
from sqlalchemy.orm import Session
from config.database import SessionLocal, engine
from config.base import Base
from models.payment import Payment
import boto3
import os
import json

@asynccontextmanager
async def lifespan(_: FastAPI):
    Base.metadata.create_all(bind=engine)
    yield


app = FastAPI(lifespan=lifespan)

AWS_REGION = os.getenv("AWS_REGION", "ap-southeast-1")
AWS_ENDPOINT_URL = os.getenv("AWS_ENDPOINT_URL")


def aws_client(service_name: str):
    kwargs = {"region_name": AWS_REGION}
    if AWS_ENDPOINT_URL:
        kwargs["endpoint_url"] = AWS_ENDPOINT_URL
    return boto3.client(service_name, **kwargs)

def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()

@app.get("/payments")
def list_payments(db: Session = Depends(get_db)):
    payments = db.query(Payment).all()
    return {"payments": payments}

@app.post("/payments")
def create_payment(account_id: int, amount: float, status: str, db: Session = Depends(get_db)):
    payment = Payment(account_id=account_id, amount=amount, status=status)
    db.add(payment)
    db.commit()
    db.refresh(payment)
    # Publish event to EventBridge
    eventbridge = aws_client("events")
    event = {
        "Source": "sbcbank.payment_service",
        "DetailType": "PaymentInitiated",
        "Detail": json.dumps({"paymentId": payment.id, "accountId": account_id, "amount": amount, "status": status}),
        "EventBusName": os.getenv("EVENT_BUS_NAME", "sbcbank-event-bus")
    }
    eventbridge.put_events(Entries=[event])
    return payment

@app.get("/payments/{payment_id}")
def get_payment(payment_id: int, db: Session = Depends(get_db)):
    payment = db.query(Payment).filter(Payment.id == payment_id).first()
    if not payment:
        raise HTTPException(status_code=404, detail="Payment not found")
    return payment

@app.post("/payments/p2p")
def initiate_p2p_payment(account_id: int, recipient_id: int, amount: float):
    stepfunctions = aws_client("stepfunctions")
    state_machine_arn = os.getenv("PAYMENT_WORKFLOW_ARN", "arn:aws:states:ap-southeast-1:000000000000:stateMachine:sbcbank-payment-workflow")
    input_payload = {
        "accountId": account_id,
        "recipientId": recipient_id,
        "amount": amount
    }
    response = stepfunctions.start_execution(
        stateMachineArn=state_machine_arn,
        input=json.dumps(input_payload)
    )
    return {"executionArn": response["executionArn"], "status": "started"}

@app.post("/payments/manual-review")
def send_to_manual_review(payment_id: int):
    sqs = aws_client("sqs")
    queue_url = os.getenv("MANUAL_REVIEW_QUEUE_URL", "https://sqs.ap-southeast-1.amazonaws.com/000000000000/sbcbank-manual-review")
    message = {"paymentId": payment_id, "reason": "FLAGGED_BY_FRAUD_DETECTION"}
    sqs.send_message(QueueUrl=queue_url, MessageBody=json.dumps(message))
    return {"status": "queued", "paymentId": payment_id}

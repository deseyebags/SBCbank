from contextlib import asynccontextmanager

from fastapi import FastAPI, Depends, HTTPException
from sqlalchemy.orm import Session
from config.database import SessionLocal, engine
from config.base import Base
from models.ledger import Ledger
import boto3
import os
import redis

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

aws_region = os.getenv("AWS_REGION", "ap-southeast-1")
aws_endpoint_url = os.getenv("AWS_ENDPOINT_URL")

dynamodb_kwargs = {"region_name": aws_region}
if aws_endpoint_url:
    dynamodb_kwargs["endpoint_url"] = aws_endpoint_url

dynamodb = boto3.resource("dynamodb", **dynamodb_kwargs)
ledger_table = dynamodb.Table(os.getenv("LEDGER_TABLE_NAME", "sbcbank-ledger"))
redis_client = redis.Redis(host=os.getenv("REDIS_HOST", "localhost"), port=int(os.getenv("REDIS_PORT", "6379")), decode_responses=True)

@app.get("/ledger")
def list_ledger(db: Session = Depends(get_db)):
    ledger = db.query(Ledger).all()
    return {"ledger": ledger}

@app.post("/ledger")
def create_ledger(description: str, amount: float, db: Session = Depends(get_db)):
    entry = Ledger(description=description, amount=amount)
    db.add(entry)
    db.commit()
    db.refresh(entry)
    return entry

@app.get("/ledger/{ledger_id}")
def get_ledger_entry(ledger_id: int, db: Session = Depends(get_db)):
    entry = db.query(Ledger).filter(Ledger.id == ledger_id).first()
    if not entry:
        raise HTTPException(status_code=404, detail="Ledger entry not found")
    return entry

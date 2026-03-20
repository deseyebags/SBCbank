from contextlib import asynccontextmanager

from fastapi import FastAPI, Depends, HTTPException
from sqlalchemy.orm import Session
from config.database import SessionLocal, engine
from config.base import Base
from models.statement import Statement
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
statement_table = dynamodb.Table(os.getenv("STATEMENT_TABLE_NAME", "sbcbank-statement"))
redis_client = redis.Redis(host=os.getenv("REDIS_HOST", "localhost"), port=int(os.getenv("REDIS_PORT", "6379")), decode_responses=True)

@app.get("/statements")
def list_statements(db: Session = Depends(get_db)):
    statements = db.query(Statement).all()
    return {"statements": statements}

@app.post("/statements")
def create_statement(account_id: int, period: str, db: Session = Depends(get_db)):
    statement = Statement(account_id=account_id, period=period)
    db.add(statement)
    db.commit()
    db.refresh(statement)
    return statement

@app.get("/statements/{statement_id}")
def get_statement(statement_id: int, db: Session = Depends(get_db)):
    statement = db.query(Statement).filter(Statement.id == statement_id).first()
    if not statement:
        raise HTTPException(status_code=404, detail="Statement not found")
    return statement

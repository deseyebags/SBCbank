from contextlib import asynccontextmanager

from fastapi import FastAPI, Depends, HTTPException
from sqlalchemy.orm import Session
from config.database import SessionLocal, engine
from config.base import Base
from models.account import Account

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

@app.get("/accounts")
def list_accounts(db: Session = Depends(get_db)):
    accounts = db.query(Account).all()
    return {"accounts": accounts}

@app.post("/accounts")
def create_account(name: str, email: str, db: Session = Depends(get_db)):
    account = Account(name=name, email=email)
    db.add(account)
    db.commit()
    db.refresh(account)
    return account

@app.get("/accounts/{account_id}")
def get_account(account_id: int, db: Session = Depends(get_db)):
    account = db.query(Account).filter(Account.id == account_id).first()
    if not account:
        raise HTTPException(status_code=404, detail="Account not found")
    return account

@app.post("/accounts/debit")
def debit_account(account_id: int, amount: float, db: Session = Depends(get_db)):
    account = db.query(Account).filter(Account.id == account_id).first()
    if not account:
        raise HTTPException(status_code=404, detail="Account not found")
    if account.balance < amount:
        raise HTTPException(status_code=400, detail="Insufficient balance")
    account.balance -= amount
    db.commit()
    db.refresh(account)
    return {"account_id": account_id, "new_balance": account.balance}

@app.post("/accounts/credit")
def credit_account(account_id: int, amount: float, db: Session = Depends(get_db)):
    account = db.query(Account).filter(Account.id == account_id).first()
    if not account:
        raise HTTPException(status_code=404, detail="Account not found")
    account.balance += amount
    db.commit()
    db.refresh(account)
    return {"account_id": account_id, "new_balance": account.balance}

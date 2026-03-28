from contextlib import asynccontextmanager

from fastapi import FastAPI, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy.orm import Session
from config.database import SessionLocal, engine
from config.base import Base
from config.auth import (
    ADMIN_PASSWORD,
    ADMIN_USERNAME,
    AuthContext,
    ensure_account_access,
    get_auth_or_internal_context,
    issue_access_token,
    require_admin_or_internal,
    require_roles,
)
from models.account import Account


class AdminLoginRequest(BaseModel):
    username: str
    password: str


class UserLoginRequest(BaseModel):
    account_id: int
    email: str

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

@app.get("/health")
def health():
    return {"status": "ok"}


@app.post("/auth/login/admin")
def login_admin(payload: AdminLoginRequest):
    if payload.username != ADMIN_USERNAME or payload.password != ADMIN_PASSWORD:
        raise HTTPException(status_code=401, detail="Invalid admin credentials")

    token = issue_access_token(subject=payload.username, role="admin")
    return {
        "access_token": token,
        "token_type": "bearer",
        "role": "admin",
        "account_id": None,
        "display_name": payload.username,
    }


@app.post("/auth/login/user")
def login_user(payload: UserLoginRequest, db: Session = Depends(get_db)):
    account = db.query(Account).filter(Account.id == payload.account_id).first()
    if not account:
        raise HTTPException(status_code=401, detail="Invalid account credentials")

    expected_email = (account.email or "").strip().lower()
    provided_email = payload.email.strip().lower()
    if expected_email != provided_email:
        raise HTTPException(status_code=401, detail="Invalid account credentials")

    token = issue_access_token(
        subject=account.email,
        role="user",
        account_id=account.id,
    )
    return {
        "access_token": token,
        "token_type": "bearer",
        "role": "user",
        "account_id": account.id,
        "display_name": account.name,
    }


@app.get("/auth/me")
def auth_me(auth: AuthContext = Depends(get_auth_or_internal_context)):
    return {
        "subject": auth.subject,
        "role": auth.role,
        "account_id": auth.account_id,
    }

@app.get("/accounts")
def list_accounts(
    _: AuthContext = Depends(require_roles("admin")),
    db: Session = Depends(get_db),
):
    accounts = db.query(Account).all()
    return {"accounts": accounts}

@app.post("/accounts")
def create_account(
    name: str,
    email: str,
    _: AuthContext = Depends(require_roles("admin")),
    db: Session = Depends(get_db),
):
    account = Account(name=name, email=email)
    db.add(account)
    db.commit()
    db.refresh(account)
    return account

@app.get("/accounts/{account_id}")
def get_account(
    account_id: int,
    auth: AuthContext = Depends(get_auth_or_internal_context),
    db: Session = Depends(get_db),
):
    account = db.query(Account).filter(Account.id == account_id).first()
    if not account:
        raise HTTPException(status_code=404, detail="Account not found")
    ensure_account_access(auth, account_id)
    return account

@app.post("/accounts/debit")
def debit_account(
    account_id: int,
    amount: float,
    _: AuthContext = Depends(require_admin_or_internal),
    db: Session = Depends(get_db),
):
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
def credit_account(
    account_id: int,
    amount: float,
    _: AuthContext = Depends(require_admin_or_internal),
    db: Session = Depends(get_db),
):
    account = db.query(Account).filter(Account.id == account_id).first()
    if not account:
        raise HTTPException(status_code=404, detail="Account not found")
    account.balance += amount
    db.commit()
    db.refresh(account)
    return {"account_id": account_id, "new_balance": account.balance}

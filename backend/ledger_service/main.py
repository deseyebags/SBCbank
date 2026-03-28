from contextlib import asynccontextmanager

from fastapi import FastAPI, Depends, HTTPException
from sqlalchemy.orm import Session
from config.auth import AuthContext, require_admin_or_internal, require_roles
from config.database import SessionLocal, engine
from config.base import Base
from models.ledger import Ledger

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

@app.get("/ledger")
def list_ledger(
    _: AuthContext = Depends(require_roles("admin")),
    db: Session = Depends(get_db),
):
    ledger = db.query(Ledger).all()
    return {"ledger": ledger}

@app.post("/ledger")
def create_ledger(
    description: str,
    amount: float,
    _: AuthContext = Depends(require_admin_or_internal),
    db: Session = Depends(get_db),
):
    entry = Ledger(description=description, amount=amount)
    db.add(entry)
    db.commit()
    db.refresh(entry)
    return entry

@app.get("/ledger/{ledger_id}")
def get_ledger_entry(
    ledger_id: int,
    _: AuthContext = Depends(require_roles("admin")),
    db: Session = Depends(get_db),
):
    entry = db.query(Ledger).filter(Ledger.id == ledger_id).first()
    if not entry:
        raise HTTPException(status_code=404, detail="Ledger entry not found")
    return entry

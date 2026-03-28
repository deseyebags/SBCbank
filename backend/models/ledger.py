from datetime import UTC, datetime

from sqlalchemy import Column, DateTime, Float, Integer, String

from config.base import Base


def utcnow() -> datetime:
    return datetime.now(UTC).replace(tzinfo=None)

class Ledger(Base):
    __tablename__ = "ledger"
    id = Column(Integer, primary_key=True, index=True)
    description = Column(String)
    amount = Column(Float)
    created_at = Column(DateTime, default=utcnow)

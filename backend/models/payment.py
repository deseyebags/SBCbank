from datetime import UTC, datetime

from sqlalchemy import Column, DateTime, Float, ForeignKey, Integer, String

from config.base import Base


def utcnow() -> datetime:
    return datetime.now(UTC).replace(tzinfo=None)

class Payment(Base):
    __tablename__ = "payments"
    id = Column(Integer, primary_key=True, index=True)
    account_id = Column(Integer, ForeignKey("accounts.id"))
    recipient_account_id = Column(Integer, nullable=True)
    amount = Column(Float, nullable=False)
    status = Column(String, nullable=False)
    execution_id = Column(String, nullable=True, unique=True)
    created_at = Column(DateTime, default=utcnow)

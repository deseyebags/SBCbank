from datetime import UTC, datetime

from sqlalchemy import Column, DateTime, Float, Integer, String

from config.base import Base


def utcnow() -> datetime:
    return datetime.now(UTC).replace(tzinfo=None)

class Account(Base):
    __tablename__ = "accounts"
    id = Column(Integer, primary_key=True, index=True)
    name = Column(String, nullable=False)
    email = Column(String, unique=True, nullable=False)
    balance = Column(Float, nullable=False, default=0.0)
    created_at = Column(DateTime, default=utcnow)

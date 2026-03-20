from sqlalchemy import Column, DateTime, Float, Integer, String

from config.base import Base

class Ledger(Base):
    __tablename__ = "ledger"
    id = Column(Integer, primary_key=True, index=True)
    description = Column(String)
    amount = Column(Float)
    created_at = Column(DateTime)

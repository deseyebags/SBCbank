from sqlalchemy import Column, DateTime, ForeignKey, Integer, String

from config.base import Base

class Statement(Base):
    __tablename__ = "statements"
    id = Column(Integer, primary_key=True, index=True)
    account_id = Column(Integer, ForeignKey("accounts.id"))
    period = Column(String)
    created_at = Column(DateTime)

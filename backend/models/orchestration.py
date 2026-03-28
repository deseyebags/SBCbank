from datetime import datetime

from sqlalchemy import Column, DateTime, Integer, String

from config.base import Base


class OrchestrationExecution(Base):
    __tablename__ = "orchestration_executions"

    id = Column(Integer, primary_key=True, index=True)
    execution_id = Column(String, nullable=False, unique=True, index=True)
    payment_id = Column(Integer, nullable=False, index=True)
    workflow_type = Column(String, nullable=False, default="P2P_PAYMENT")
    status = Column(String, nullable=False)
    retry_count = Column(Integer, nullable=False, default=0)
    error_message = Column(String, nullable=True)
    created_at = Column(DateTime, nullable=False, default=datetime.utcnow)
    updated_at = Column(DateTime, nullable=False, default=datetime.utcnow, onupdate=datetime.utcnow)
    completed_at = Column(DateTime, nullable=True)

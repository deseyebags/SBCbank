# pyright: reportMissingImports=false, reportUnusedImport=false

import sys
from pathlib import Path
from typing import Generator

import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

# Ensure imports resolve when tests run from repository root.
BACKEND_DIR = Path(__file__).resolve().parents[1]
if str(BACKEND_DIR) not in sys.path:
    sys.path.insert(0, str(BACKEND_DIR))

from config.base import Base
import account_service.main as account_main
from account_service.main import app, get_db
import payment_service.main as payment_main
import ledger_service.main as ledger_main
import statement_service.main as statement_main

# Register model metadata before create_all.
import models.account  # noqa: F401
import models.payment  # noqa: F401
import models.ledger  # noqa: F401
import models.statement  # noqa: F401


def _service_client(service_module, service_app, service_get_db) -> Generator:
    test_engine = create_engine(
        "sqlite://",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    testing_session_local = sessionmaker(autocommit=False, autoflush=False, bind=test_engine)
    service_module.engine = test_engine
    service_module.SessionLocal = testing_session_local
    Base.metadata.create_all(bind=test_engine)

    def override_get_db():
        db = testing_session_local()
        try:
            yield db
        finally:
            db.close()

    service_app.dependency_overrides[service_get_db] = override_get_db

    from fastapi.testclient import TestClient

    with TestClient(service_app) as test_client:
        yield test_client

    service_app.dependency_overrides.clear()
    Base.metadata.drop_all(bind=test_engine)


@pytest.fixture()
def client():
    yield from _service_client(account_main, app, get_db)


@pytest.fixture()
def payment_client():
    yield from _service_client(payment_main, payment_main.app, payment_main.get_db)


@pytest.fixture()
def ledger_client():
    yield from _service_client(ledger_main, ledger_main.app, ledger_main.get_db)


@pytest.fixture()
def statement_client():
    yield from _service_client(statement_main, statement_main.app, statement_main.get_db)

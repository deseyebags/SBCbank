from datetime import datetime

import statement_service.main as statement_main
from models.account import Account
from models.payment import Payment


def _seed_account_with_payments():
    db = statement_main.SessionLocal()
    try:
        db.add_all(
            [
                Account(id=1, name="Alice", email="alice@example.com", balance=500.0),
                Account(id=2, name="Bob", email="bob@example.com", balance=300.0),
            ]
        )
        db.add_all(
            [
                Payment(
                    account_id=1,
                    recipient_account_id=2,
                    amount=50.0,
                    status="SUCCESS",
                    created_at=datetime(2026, 3, 5, 10, 0, 0),
                ),
                Payment(
                    account_id=2,
                    recipient_account_id=1,
                    amount=30.0,
                    status="SUCCESS",
                    created_at=datetime(2026, 3, 7, 12, 0, 0),
                ),
                Payment(
                    account_id=1,
                    recipient_account_id=2,
                    amount=10.0,
                    status="SUCCESS",
                    created_at=datetime(2026, 4, 2, 10, 0, 0),
                ),
            ]
        )
        db.commit()
    finally:
        db.close()


def test_create_and_get_statement(statement_client, monkeypatch, admin_headers):
    _seed_account_with_payments()

    emitted = {}

    def _fake_publish(payload):
        emitted["payload"] = payload

    monkeypatch.setattr(statement_main, "publish_statement_notification", _fake_publish)

    create_resp = statement_client.post(
        "/statements",
        params={"account_id": 1, "period": "2026-03"},
        headers=admin_headers,
    )
    assert create_resp.status_code == 200
    statement_id = create_resp.json()["id"]

    get_resp = statement_client.get(f"/statements/{statement_id}", headers=admin_headers)
    assert get_resp.status_code == 200
    body = get_resp.json()
    assert body["account_id"] == 1
    assert body["period"] == "2026-03"

    assert emitted["payload"]["recipient"]["email"] == "alice@example.com"
    assert emitted["payload"]["summary"]["transaction_count"] == 2
    assert emitted["payload"]["summary"]["total_debits"] == 50.0
    assert emitted["payload"]["summary"]["total_credits"] == 30.0


def test_list_statements(statement_client, monkeypatch, admin_headers, user_headers_factory):
    db = statement_main.SessionLocal()
    try:
        db.add(Account(id=2, name="Dina", email="dina@example.com", balance=100.0))
        db.commit()
    finally:
        db.close()

    monkeypatch.setattr(statement_main, "publish_statement_notification", lambda _: None)

    statement_client.post(
        "/statements",
        params={"account_id": 2, "period": "2026-02"},
        headers=admin_headers,
    )
    response = statement_client.get("/statements", headers=admin_headers)
    assert response.status_code == 200
    assert "statements" in response.json()

    user_response = statement_client.get("/statements", headers=user_headers_factory(2))
    assert user_response.status_code == 200
    assert len(user_response.json()["statements"]) == 1

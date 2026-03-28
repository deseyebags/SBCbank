import payment_service.main as payment_main


class _MockResponse:
    def __init__(self, payload, status_code=200):
        self._payload = payload
        self.status_code = status_code

    def raise_for_status(self):
        if self.status_code >= 400:
            raise RuntimeError("HTTP error")

    def json(self):
        return self._payload


def test_create_payment(payment_client, admin_headers):
    response = payment_client.post(
        "/payments",
        params={"account_id": 1, "amount": 12.5, "status": "PENDING"},
        headers=admin_headers,
    )

    assert response.status_code == 200
    body = response.json()
    assert body["amount"] == 12.5


def test_p2p_delegates_to_orchestrator(payment_client, monkeypatch, user_headers_factory):
    captured = {}

    def _fake_post(url, json, headers, timeout):
        captured["url"] = url
        captured["json"] = json
        captured["headers"] = headers
        captured["timeout"] = timeout
        return _MockResponse(
            {
                "execution_id": json["execution_id"],
                "workflow_status": "COMPLETED",
                "payment_status": "SUCCESS",
            }
        )

    monkeypatch.setattr(payment_main.requests, "post", _fake_post)

    response = payment_client.post(
        "/payments/p2p",
        params={"account_id": 100, "recipient_id": 200, "amount": 50.0},
        headers=user_headers_factory(100),
    )

    assert response.status_code == 200
    body = response.json()
    assert body["status"] == "SUCCESS"
    assert body["workflow_status"] == "COMPLETED"
    assert "execution_id" in body
    assert captured["url"].endswith("/internal/orchestrations/payments")
    assert captured["json"]["payer_account_id"] == 100
    assert "X-Internal-Token" in captured["headers"]


def test_user_cannot_create_p2p_for_other_account(payment_client, user_headers_factory):
    response = payment_client.post(
        "/payments/p2p",
        params={"account_id": 999, "recipient_id": 200, "amount": 50.0},
        headers=user_headers_factory(100),
    )

    assert response.status_code == 403

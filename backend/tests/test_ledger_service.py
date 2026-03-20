def test_create_and_get_ledger_entry(ledger_client):
    create_resp = ledger_client.post("/ledger", params={"description": "salary", "amount": 2000.0})
    assert create_resp.status_code == 200
    entry_id = create_resp.json()["id"]

    get_resp = ledger_client.get(f"/ledger/{entry_id}")
    assert get_resp.status_code == 200
    body = get_resp.json()
    assert body["description"] == "salary"
    assert body["amount"] == 2000.0


def test_list_ledger(ledger_client):
    ledger_client.post("/ledger", params={"description": "coffee", "amount": -5.5})
    response = ledger_client.get("/ledger")
    assert response.status_code == 200
    assert "ledger" in response.json()

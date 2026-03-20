def test_create_and_get_statement(statement_client):
    create_resp = statement_client.post(
        "/statements",
        params={"account_id": 1, "period": "2026-03"},
    )
    assert create_resp.status_code == 200
    statement_id = create_resp.json()["id"]

    get_resp = statement_client.get(f"/statements/{statement_id}")
    assert get_resp.status_code == 200
    body = get_resp.json()
    assert body["account_id"] == 1
    assert body["period"] == "2026-03"


def test_list_statements(statement_client):
    statement_client.post("/statements", params={"account_id": 2, "period": "2026-02"})
    response = statement_client.get("/statements")
    assert response.status_code == 200
    assert "statements" in response.json()

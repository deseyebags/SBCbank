def test_list_accounts(client):
    response = client.get("/accounts")
    assert response.status_code == 200
    assert "accounts" in response.json()

def test_create_account(client):
    response = client.post("/accounts", params={"name": "Alice", "email": "alice@example.com"})
    assert response.status_code == 200
    assert response.json()["name"] == "Alice"
    assert response.json()["email"] == "alice@example.com"

def test_get_account(client):
    # Create account first
    create_resp = client.post("/accounts", params={"name": "Bob", "email": "bob@example.com"})
    account_id = create_resp.json()["id"]
    response = client.get(f"/accounts/{account_id}")
    assert response.status_code == 200
    assert response.json()["id"] == account_id

def test_debit_account(client):
    # Create account with balance
    create_resp = client.post("/accounts", params={"name": "Carol", "email": "carol@example.com"})
    account_id = create_resp.json()["id"]
    # Credit first to ensure balance
    client.post("/accounts/credit", params={"account_id": account_id, "amount": 100.0})
    response = client.post("/accounts/debit", params={"account_id": account_id, "amount": 50.0})
    assert response.status_code == 200
    assert response.json()["new_balance"] == 50.0

def test_credit_account(client):
    # Create account
    create_resp = client.post("/accounts", params={"name": "Dave", "email": "dave@example.com"})
    account_id = create_resp.json()["id"]
    response = client.post("/accounts/credit", params={"account_id": account_id, "amount": 75.0})
    assert response.status_code == 200
    assert response.json()["new_balance"] == 75.0

def test_debit_insufficient_balance(client):
    create_resp = client.post("/accounts", params={"name": "Eve", "email": "eve@example.com"})
    account_id = create_resp.json()["id"]
    response = client.post("/accounts/debit", params={"account_id": account_id, "amount": 10.0})
    assert response.status_code == 400
    assert response.json()["detail"] == "Insufficient balance"

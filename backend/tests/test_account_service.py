def test_admin_login(client):
    response = client.post(
        "/auth/login/admin",
        json={"username": "admin", "password": "admin123"},
    )
    assert response.status_code == 200
    assert response.json()["role"] == "admin"
    assert response.json()["access_token"]


def test_list_accounts(client, admin_headers):
    response = client.get("/accounts", headers=admin_headers)
    assert response.status_code == 200
    assert "accounts" in response.json()

def test_create_account(client, admin_headers):
    response = client.post(
        "/accounts",
        params={"name": "Alice", "email": "alice@example.com"},
        headers=admin_headers,
    )
    assert response.status_code == 200
    assert response.json()["name"] == "Alice"
    assert response.json()["email"] == "alice@example.com"


def test_user_signup_without_admin_auth(client):
    response = client.post(
        "/accounts",
        params={"name": "Signup User", "email": "signup@example.com"},
    )
    assert response.status_code == 200
    assert response.json()["email"] == "signup@example.com"


def test_signup_duplicate_email_conflict(client):
    first = client.post(
        "/accounts",
        params={"name": "First", "email": "dupe@example.com"},
    )
    assert first.status_code == 200

    second = client.post(
        "/accounts",
        params={"name": "Second", "email": "dupe@example.com"},
    )
    assert second.status_code == 409
    assert second.json()["detail"] == "Email is already registered"

def test_get_account(client, admin_headers, user_headers_factory):
    # Create account first
    create_resp = client.post(
        "/accounts",
        params={"name": "Bob", "email": "bob@example.com"},
        headers=admin_headers,
    )
    account_id = create_resp.json()["id"]
    user_headers = user_headers_factory(account_id)
    response = client.get(f"/accounts/{account_id}", headers=user_headers)
    assert response.status_code == 200
    assert response.json()["id"] == account_id

def test_debit_account(client, admin_headers):
    # Create account with balance
    create_resp = client.post(
        "/accounts",
        params={"name": "Carol", "email": "carol@example.com"},
        headers=admin_headers,
    )
    account_id = create_resp.json()["id"]
    # Credit first to ensure balance
    client.post(
        "/accounts/credit",
        params={"account_id": account_id, "amount": 100.0},
        headers=admin_headers,
    )
    response = client.post(
        "/accounts/debit",
        params={"account_id": account_id, "amount": 50.0},
        headers=admin_headers,
    )
    assert response.status_code == 200
    assert response.json()["new_balance"] == 50.0

def test_credit_account(client, admin_headers):
    # Create account
    create_resp = client.post(
        "/accounts",
        params={"name": "Dave", "email": "dave@example.com"},
        headers=admin_headers,
    )
    account_id = create_resp.json()["id"]
    response = client.post(
        "/accounts/credit",
        params={"account_id": account_id, "amount": 75.0},
        headers=admin_headers,
    )
    assert response.status_code == 200
    assert response.json()["new_balance"] == 75.0


def test_user_can_credit_own_account(client, admin_headers, user_headers_factory):
    create_resp = client.post(
        "/accounts",
        params={"name": "Own Topup", "email": "owntopup@example.com"},
        headers=admin_headers,
    )
    account_id = create_resp.json()["id"]

    response = client.post(
        "/accounts/credit",
        params={"account_id": account_id, "amount": 25.0},
        headers=user_headers_factory(account_id),
    )

    assert response.status_code == 200
    assert response.json()["new_balance"] == 25.0


def test_user_cannot_credit_other_account(client, admin_headers, user_headers_factory):
    owner_resp = client.post(
        "/accounts",
        params={"name": "Owner", "email": "owner@example.com"},
        headers=admin_headers,
    )
    owner_account_id = owner_resp.json()["id"]

    target_resp = client.post(
        "/accounts",
        params={"name": "Target", "email": "target@example.com"},
        headers=admin_headers,
    )
    target_account_id = target_resp.json()["id"]

    response = client.post(
        "/accounts/credit",
        params={"account_id": target_account_id, "amount": 20.0},
        headers=user_headers_factory(owner_account_id),
    )

    assert response.status_code == 403

def test_debit_insufficient_balance(client, admin_headers):
    create_resp = client.post(
        "/accounts",
        params={"name": "Eve", "email": "eve@example.com"},
        headers=admin_headers,
    )
    account_id = create_resp.json()["id"]
    response = client.post(
        "/accounts/debit",
        params={"account_id": account_id, "amount": 10.0},
        headers=admin_headers,
    )
    assert response.status_code == 400
    assert response.json()["detail"] == "Insufficient balance"


def test_user_cannot_list_accounts(client, admin_headers, user_headers_factory):
    create_resp = client.post(
        "/accounts",
        params={"name": "Frank", "email": "frank@example.com"},
        headers=admin_headers,
    )
    account_id = create_resp.json()["id"]

    response = client.get("/accounts", headers=user_headers_factory(account_id))
    assert response.status_code == 403

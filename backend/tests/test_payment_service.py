import payment_service.main as payment_main


class _MockEventsClient:
    def __init__(self):
        self.entries = None

    def put_events(self, Entries):
        self.entries = Entries
        return {"FailedEntryCount": 0}


class _MockStepFunctionsClient:
    def start_execution(self, stateMachineArn, input):
        return {"executionArn": f"{stateMachineArn}:execution:unit-test"}


class _MockSqsClient:
    def __init__(self):
        self.last_message = None

    def send_message(self, QueueUrl, MessageBody):
        self.last_message = {"QueueUrl": QueueUrl, "MessageBody": MessageBody}
        return {"MessageId": "msg-1"}


def test_create_payment_publishes_event(payment_client, monkeypatch):
    mock_events = _MockEventsClient()

    def _fake_client(service_name: str):
        if service_name == "events":
            return mock_events
        raise AssertionError(f"Unexpected service: {service_name}")

    monkeypatch.setattr(payment_main, "aws_client", _fake_client)

    response = payment_client.post(
        "/payments",
        params={"account_id": 1, "amount": 12.5, "status": "PENDING"},
    )

    assert response.status_code == 200
    body = response.json()
    assert body["amount"] == 12.5
    assert mock_events.entries is not None
    assert mock_events.entries[0]["DetailType"] == "PaymentInitiated"


def test_p2p_starts_step_function_execution(payment_client, monkeypatch):
    mock_sf = _MockStepFunctionsClient()

    def _fake_client(service_name: str):
        if service_name == "stepfunctions":
            return mock_sf
        raise AssertionError(f"Unexpected service: {service_name}")

    monkeypatch.setattr(payment_main, "aws_client", _fake_client)

    response = payment_client.post(
        "/payments/p2p",
        params={"account_id": 100, "recipient_id": 200, "amount": 50.0},
    )

    assert response.status_code == 200
    body = response.json()
    assert body["status"] == "started"
    assert "executionArn" in body


def test_manual_review_sends_sqs_message(payment_client, monkeypatch):
    mock_sqs = _MockSqsClient()

    def _fake_client(service_name: str):
        if service_name == "sqs":
            return mock_sqs
        raise AssertionError(f"Unexpected service: {service_name}")

    monkeypatch.setattr(payment_main, "aws_client", _fake_client)

    response = payment_client.post("/payments/manual-review", params={"payment_id": 77})

    assert response.status_code == 200
    body = response.json()
    assert body["status"] == "queued"
    assert mock_sqs.last_message is not None

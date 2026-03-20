import json
from datetime import datetime, timezone


def handler(event, context):
    detail = event.get("detail", {}) if isinstance(event, dict) else {}
    recipient = detail.get("recipient", "customer@example.com")
    event_type = detail.get("eventType", "transaction.created")

    payload = {
        "status": "queued",
        "channel": "email",
        "recipient": recipient,
        "eventType": event_type,
        "processedAt": datetime.now(timezone.utc).isoformat(),
        "requestId": getattr(context, "aws_request_id", None),
    }

    return {
        "statusCode": 200,
        "body": json.dumps(payload),
    }

# EventBridge trigger example
# This Lambda is triggered by EventBridge for notification events
# Handler expects event with notification details

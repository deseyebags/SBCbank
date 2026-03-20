import json
from datetime import datetime, timezone


def handler(event, context):
    detail = event.get("detail", {}) if isinstance(event, dict) else {}
    amount = float(detail.get("amount", 0))

    decision = "APPROVE"
    risk_score = 12
    if amount >= 5000:
        decision = "MANUAL_REVIEW"
        risk_score = 67

    payload = {
        "decision": decision,
        "riskScore": risk_score,
        "evaluatedAt": datetime.now(timezone.utc).isoformat(),
        "requestId": getattr(context, "aws_request_id", None),
    }

    return {
        "statusCode": 200,
        "body": json.dumps(payload),
    }

# EventBridge/Step Functions trigger example
# This Lambda is triggered by Step Functions in payment workflow
# Handler expects event with payment details

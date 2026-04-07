import json
from datetime import datetime, timezone


def handler(event, context):
    # Print the full event payload so default-bus producers are visible in logs.
    print(json.dumps(event, default=str))

    detail_type = event.get("detail-type") if isinstance(event, dict) else None
    source = event.get("source") if isinstance(event, dict) else None

    payload = {
        "status": "captured",
        "capturedAt": datetime.now(timezone.utc).isoformat(),
        "source": source,
        "detailType": detail_type,
        "requestId": getattr(context, "aws_request_id", None),
    }

    return {
        "statusCode": 200,
        "body": json.dumps(payload),
    }

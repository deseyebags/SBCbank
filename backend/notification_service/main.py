from contextlib import asynccontextmanager
from email.message import EmailMessage
import json
import logging
import os
import smtplib
import threading
import time
from typing import Any

from fastapi import FastAPI
import pika

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("notification_service")

RABBITMQ_HOST = os.getenv("RABBITMQ_HOST", "rabbitmq")
RABBITMQ_PORT = int(os.getenv("RABBITMQ_PORT", "5672"))
RABBITMQ_USER = os.getenv("RABBITMQ_USER", "scbbank")
RABBITMQ_PASSWORD = os.getenv("RABBITMQ_PASSWORD", "scbbank")
STATEMENT_NOTIFICATION_QUEUE = os.getenv("STATEMENT_NOTIFICATION_QUEUE", "statement_notifications")
NOTIFICATION_POLL_INTERVAL_SECONDS = float(os.getenv("NOTIFICATION_POLL_INTERVAL_SECONDS", "1"))
RABBITMQ_RETRY_DELAY_SECONDS = float(os.getenv("RABBITMQ_RETRY_DELAY_SECONDS", "5"))

SMTP_HOST = os.getenv("SMTP_HOST")
SMTP_PORT = int(os.getenv("SMTP_PORT", "587"))
SMTP_USERNAME = os.getenv("SMTP_USERNAME")
SMTP_PASSWORD = os.getenv("SMTP_PASSWORD")
SMTP_USE_TLS = os.getenv("SMTP_USE_TLS", "false").lower() == "true"
SMTP_SENDER_EMAIL = os.getenv("SMTP_SENDER_EMAIL", "no-reply@scbbank.local")

stop_event = threading.Event()


def create_rabbitmq_connection() -> pika.BlockingConnection:
    credentials = pika.PlainCredentials(RABBITMQ_USER, RABBITMQ_PASSWORD)
    parameters = pika.ConnectionParameters(
        host=RABBITMQ_HOST,
        port=RABBITMQ_PORT,
        credentials=credentials,
    )
    return pika.BlockingConnection(parameters)


def send_email(to_email: str, subject: str, body: str) -> None:
    if not SMTP_HOST:
        logger.info("MOCK email to %s | Subject: %s\n%s", to_email, subject, body)
        return

    message = EmailMessage()
    message["From"] = SMTP_SENDER_EMAIL
    message["To"] = to_email
    message["Subject"] = subject
    message.set_content(body)

    with smtplib.SMTP(SMTP_HOST, SMTP_PORT, timeout=10) as smtp:
        if SMTP_USE_TLS:
            smtp.starttls()
        if SMTP_USERNAME and SMTP_PASSWORD:
            smtp.login(SMTP_USERNAME, SMTP_PASSWORD)
        smtp.send_message(message)


def format_statement_email(payload: dict[str, Any]) -> tuple[str, str, str]:
    recipient = payload.get("recipient", {})
    statement = payload.get("statement", {})
    summary = payload.get("summary", {})
    transactions = payload.get("transactions", [])

    email = recipient.get("email", "")
    subject = f"Your scbbank statement for {statement.get('period', 'unknown period')}"

    lines = [
        f"Hello {recipient.get('name', 'customer')},",
        "",
        f"Statement ID: {statement.get('statement_id')}",
        f"Period: {statement.get('period')}",
        f"Generated At: {statement.get('generated_at')}",
        "",
        "Summary:",
        f"- Transactions: {summary.get('transaction_count', 0)}",
        f"- Total Debits: {summary.get('total_debits', 0)}",
        f"- Total Credits: {summary.get('total_credits', 0)}",
        f"- Net Total: {summary.get('net_total', 0)}",
        "",
        "Transactions:",
    ]

    if not transactions:
        lines.append("- No transactions for this period.")
    else:
        for item in transactions:
            lines.append(
                "- "
                f"Payment #{item.get('payment_id')} | "
                f"{item.get('direction')} {item.get('amount')} | "
                f"Counterparty {item.get('counterparty_account_id')} | "
                f"Status {item.get('status')}"
            )

    return email, subject, "\n".join(lines)


def process_notification(payload: dict[str, Any]) -> None:
    if payload.get("type") != "statement.generated":
        logger.info("Skipping unsupported notification type: %s", payload.get("type"))
        return

    email, subject, body = format_statement_email(payload)
    if not email:
        logger.warning("Skipping notification because recipient email is missing")
        return

    send_email(email, subject, body)


def consume_notifications(stop_signal: threading.Event) -> None:
    logger.info("Notification consumer started")

    while not stop_signal.is_set():
        connection = None
        channel = None
        try:
            connection = create_rabbitmq_connection()
            channel = connection.channel()
            channel.queue_declare(queue=STATEMENT_NOTIFICATION_QUEUE, durable=True)

            while not stop_signal.is_set():
                method, _, body = channel.basic_get(
                    queue=STATEMENT_NOTIFICATION_QUEUE,
                    auto_ack=False,
                )
                if method is None:
                    time.sleep(NOTIFICATION_POLL_INTERVAL_SECONDS)
                    continue

                try:
                    payload = json.loads(body.decode("utf-8"))
                    process_notification(payload)
                    channel.basic_ack(method.delivery_tag)
                except (json.JSONDecodeError, KeyError, TypeError, ValueError, smtplib.SMTPException, pika.exceptions.AMQPError, OSError):
                    logger.exception("Failed to process notification message")
                    channel.basic_nack(method.delivery_tag, requeue=False)
        except (pika.exceptions.AMQPError, OSError):
            logger.exception("RabbitMQ consumer error. Retrying...")
            time.sleep(RABBITMQ_RETRY_DELAY_SECONDS)
        finally:
            try:
                if channel and channel.is_open:
                    channel.close()
            except (pika.exceptions.AMQPError, OSError):
                pass
            try:
                if connection and connection.is_open:
                    connection.close()
            except (pika.exceptions.AMQPError, OSError):
                pass

    logger.info("Notification consumer stopped")


@asynccontextmanager
async def lifespan(_: FastAPI):
    stop_event.clear()
    thread = threading.Thread(
        target=consume_notifications,
        args=(stop_event,),
        daemon=True,
    )
    thread.start()
    app.state.consumer_thread = thread

    yield

    stop_event.set()
    consumer = getattr(app.state, "consumer_thread", None)
    if consumer:
        consumer.join(timeout=5)


app = FastAPI(lifespan=lifespan)


@app.get("/health")
def health():
    consumer = getattr(app.state, "consumer_thread", None)
    return {
        "status": "ok",
        "queue": STATEMENT_NOTIFICATION_QUEUE,
        "consumer_running": bool(consumer and consumer.is_alive()),
    }

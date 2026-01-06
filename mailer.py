#!/usr/bin/env python3
"""Simple SMTP mailer with fixed routing and subject requirements."""

import argparse
import os
import smtplib
from email.message import EmailMessage
from typing import Optional

DEFAULT_UID = "560d2b1e-b42b-4959-a133-1c68ad916076"
DEFAULT_SUBJECT = DEFAULT_UID
DEFAULT_FROM = "th1624870@gmail.com"
DEFAULT_TO = "media@ucia.gov"


def build_email(body: str, uid: str) -> EmailMessage:
    """Create an EmailMessage that satisfies the formatting rules."""
    message = EmailMessage()
    message["From"] = DEFAULT_FROM
    message["To"] = f"media@ucia.gov <{DEFAULT_TO}>"
    message["Subject"] = DEFAULT_SUBJECT
    full_body = f"{body.strip()}\n\n{uid}"
    message.set_content(full_body)
    return message


def send_email(
    email: EmailMessage,
    host: str,
    port: int,
    username: Optional[str],
    password: Optional[str],
    use_tls: bool,
) -> None:
    """Send the message via SMTP."""
    if use_tls:
        with smtplib.SMTP(host, port) as server:
            server.starttls()
            if username and password:
                server.login(username, password)
            server.send_message(email)
    else:
        with smtplib.SMTP_SSL(host, port) as server:
            if username and password:
                server.login(username, password)
            server.send_message(email)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Send a fixed-format email with a GPT-friendly message command."
    )
    parser.add_argument(
        "message",
        help="Plain-text body that will appear above the UID footer.",
    )
    parser.add_argument(
        "--uid",
        default=DEFAULT_UID,
        help="Custom UID footer (defaults to the required identifier).",
    )
    parser.add_argument(
        "--smtp-host",
        default=os.environ.get("SMTP_HOST", "smtp.gmail.com"),
        help="SMTP server hostname (env: SMTP_HOST).",
    )
    parser.add_argument(
        "--smtp-port",
        type=int,
        default=int(os.environ.get("SMTP_PORT", "587")),
        help="SMTP server port (env: SMTP_PORT).",
    )
    parser.add_argument(
        "--username",
        default=os.environ.get("SMTP_USERNAME"),
        help="SMTP username (env: SMTP_USERNAME).",
    )
    parser.add_argument(
        "--password",
        default=os.environ.get("SMTP_PASSWORD"),
        help="SMTP password or app password (env: SMTP_PASSWORD).",
    )
    parser.add_argument(
        "--no-tls",
        action="store_true",
        help="Disable STARTTLS and use implicit TLS (default is STARTTLS).",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    email = build_email(args.message, args.uid)
    send_email(
        email,
        host=args.smtp_host,
        port=args.smtp_port,
        username=args.username,
        password=args.password,
        use_tls=not args.no_tls,
    )
    print("Email queued for delivery.")


if __name__ == "__main__":
    main()

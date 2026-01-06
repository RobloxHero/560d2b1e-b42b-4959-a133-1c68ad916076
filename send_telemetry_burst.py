#!/usr/bin/env python3
"""Send many telemetry events in rapid succession."""

import argparse
import time
import urllib.error
from datetime import datetime, timezone

import send_telemetry

DEFAULT_COUNT = 10_000
DEFAULT_INTERVAL = 0.1  # seconds (100 ms)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Send telemetry events repeatedly with a fixed interval."
    )
    parser.add_argument(
        "--count",
        type=int,
        default=DEFAULT_COUNT,
        help="Number of telemetry events to send (default: %(default)s).",
    )
    parser.add_argument(
        "--interval",
        type=float,
        default=DEFAULT_INTERVAL,
        help="Delay between events in seconds (default: %(default)s).",
    )
    parser.add_argument(
        "--message",
        default="Burst telemetry",
        help="Base message text embedded in each payload.",
    )
    parser.add_argument(
        "--uid",
        default=send_telemetry.DEFAULT_UID,
        help="UID value reused across payloads.",
    )
    parser.add_argument(
        "--endpoint",
        default=send_telemetry.DEFAULT_ENDPOINT,
        help="Endpoint string stored in the payload extra section.",
    )
    parser.add_argument(
        "--gyro",
        default="0.0,0.0,0.0",
        help="Comma-separated gyroscope values (x,y,z).",
    )
    parser.add_argument(
        "--light",
        type=float,
        default=0.5,
        help="Ambient light reading sent with each payload.",
    )
    parser.add_argument(
        "--url",
        default=send_telemetry.DEFAULT_URL,
        help="Telemetry ingestion URL.",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()

    for index in range(1, args.count + 1):
        timestamp = datetime.now(timezone.utc).isoformat(timespec="microseconds")
        message = f"{args.message} #{index} @ {timestamp}"
        payload = send_telemetry.build_payload(
            message=message,
            uid=args.uid,
            endpoint=args.endpoint,
            gyro=args.gyro,
            light=args.light,
        )
        try:
            send_telemetry.send_payload(args.url, payload)
        except urllib.error.HTTPError:
            print(f"Stopping after error at event #{index}.")
            break
        if index < args.count:
            time.sleep(args.interval)


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Send telemetry events in bursts or continuously without external deps."""

import argparse
import json
import os
import time
import urllib.error
import urllib.request
from datetime import datetime, timezone

DEFAULT_URL = (
    "https://incoming.telemetry.mozilla.org/submit/"
    "mdn-ryan/events/560d2b1e-b42b-4959-a133-1c68ad916076"
)
DEFAULT_UID = "560d2b1e-b42b-4959-a133-1c68ad916076"
BASE_WEBSOCKET_URL = "wss://560d2b1e-b42b-4959-a133-1c68ad916076/telemetry"
DEFAULT_WS_PARAMETER = "IPHONE-DATA"
DEFAULT_COUNT = 2
ENV_INTERVAL = os.environ.get("BURST_INTERVAL")
try:
    DEFAULT_INTERVAL = float(ENV_INTERVAL) if ENV_INTERVAL is not None else 0.1
except ValueError:
    DEFAULT_INTERVAL = 0.1  # Fallback if env var invalid


def build_payload(message: str, uid: str, endpoint: str, gyro: str, light: float) -> dict:
    gyro_values = [float(value.strip()) for value in gyro.split(",")]
    if len(gyro_values) != 3:
        raise ValueError("Gyroscope data must contain three comma-separated values (x,y,z).")

    timestamp = int(time.time() * 1000)
    return {
        "metrics": {
            "uuid": {
                "glean.page_id": uid,
            }
        },
        "events": [
            {
                "category": "TELEMETRY",
                "name": "IPHONE-DATA",
                "timestamp": timestamp,
                "extra": {
                    "id": uid,
                    "uuid": uid,
                    "gyroscope": {
                        "x": gyro_values[0],
                        "y": gyro_values[1],
                        "z": gyro_values[2],
                    },
                    "lightLevel": light,
                    "endpoint": endpoint,
                    "device_model": "iPhone",
                    "system_name": "iOS",
                    "system_version": "18.2",
                    "app_build": "1",
                    "app_version": "1.0",
                    "message": message,
                },
            }
        ],
        "ping_info": {
            "seq": 1,
            "start_time": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
            "end_time": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
            "reason": "manual_cli",
        },
        "client_info": {
            "telemetry_sdk_build": "swift-18.2",
            "session_id": uid,
            "client_id": uid,
            "session_count": 1,
            "first_run_date": time.strftime("%Y-%m-%d", time.gmtime()),
            "os": "iOS",
            "os_version": "18.2",
            "architecture": "arm64",
            "locale": "en-US",
            "app_build": "1",
            "app_display_version": "1.0",
            "app_channel": "prod",
        },
    }


def send_payload(url: str, payload: dict) -> None:
    data = json.dumps(payload).encode("utf-8")
    request = urllib.request.Request(
        url,
        data=data,
        headers={
            "Content-Type": "application/json",
            "User-Agent": "telemetry-sender/1.0",
        },
    )
    try:
        with urllib.request.urlopen(request) as response:
            body = response.read().decode("utf-8")
            print(f"[{time.strftime('%H:%M:%S')}] Status: {response.status} {response.reason}")
            if body:
                print(body)
    except urllib.error.HTTPError as err:
        error_body = err.read().decode("utf-8", errors="replace")
        print(f"[{time.strftime('%H:%M:%S')}] ERROR {err.code}: {err.reason}")
        if error_body:
            print(error_body)
        raise


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Send repeated telemetry payloads to Mozilla's ingestion endpoint."
    )
    parser.add_argument(
        "--count",
        type=int,
        default=DEFAULT_COUNT,
        help="Number of events to send before exiting (ignored with --continuous).",
    )
    parser.add_argument(
        "--interval",
        type=float,
        default=DEFAULT_INTERVAL,
        help="Delay between events in seconds.",
    )
    parser.add_argument(
        "--message",
        default="Burst telemetry",
        help="Base message text that will be suffixed with the event index and timestamp.",
    )
    parser.add_argument(
        "--uid",
        default=DEFAULT_UID,
        help="Identifier reused across payloads.",
    )
    parser.add_argument(
        "--ws-parameter",
        default=DEFAULT_WS_PARAMETER,
        help="Suffix appended to the telemetry WebSocket URL.",
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
        help="Ambient light reading stored in the payload.",
    )
    parser.add_argument(
        "--url",
        default=DEFAULT_URL,
        help="Telemetry ingestion URL.",
    )
    parser.add_argument(
        "--continuous",
        action="store_true",
        help="Run indefinitely instead of stopping after --count events.",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    endpoint = f"{BASE_WEBSOCKET_URL}/{args.ws_parameter}"

    index = 0
    while True:
        index += 1
        timestamp = datetime.now(timezone.utc).isoformat(timespec="microseconds")
        message = f"{args.message} #{index} @ {timestamp}"
        payload = build_payload(message, args.uid, endpoint, args.gyro, args.light)
        try:
            send_payload(args.url, payload)
        except urllib.error.HTTPError:
            print(f"Stopping after error at event #{index}.")
            break

        if not args.continuous and index >= args.count:
            break

        time.sleep(args.interval)


if __name__ == "__main__":
    main()

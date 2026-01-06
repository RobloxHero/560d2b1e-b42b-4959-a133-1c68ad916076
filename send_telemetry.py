#!/usr/bin/env python3
"""Send a telemetry event to the Mozilla ingestion endpoint."""

import argparse
import json
import time
import urllib.request

DEFAULT_URL = (
    "https://incoming.telemetry.mozilla.org/submit/"
    "mdn-fred/events/1/9d309dcd-5d75-4797-808b-6f3d770604c7"
)
DEFAULT_UID = "560d2b1e-b42b-4959-a133-1c68ad916076"
DEFAULT_ENDPOINT = "wss://560d2b1e-b42b-4959-a133-1c68ad916076/telemetry/IPHONE-DATA"


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
    with urllib.request.urlopen(request) as response:
        print(f"Status: {response.status}")
        print(response.read().decode("utf-8"))


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Send telemetry data to Mozilla's ingestion endpoint."
    )
    parser.add_argument(
        "message",
        help="Text content that will be added to the telemetry payload.",
    )
    parser.add_argument(
        "--url",
        default=DEFAULT_URL,
        help="Telemetry ingestion URL (default: %(default)s).",
    )
    parser.add_argument(
        "--uid",
        default=DEFAULT_UID,
        help="Identifier used across the payload (default: %(default)s).",
    )
    parser.add_argument(
        "--endpoint",
        default=DEFAULT_ENDPOINT,
        help="Value stored in the payload's endpoint field.",
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
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    payload = build_payload(args.message, args.uid, args.endpoint, args.gyro, args.light)
    send_payload(args.url, payload)


if __name__ == "__main__":
    main()

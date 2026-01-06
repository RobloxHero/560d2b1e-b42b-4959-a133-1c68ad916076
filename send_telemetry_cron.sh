#!/bin/bash
# Continuously POST telemetry every 5 seconds.

set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"

while true; do
  timestamp="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  python3 "$SCRIPT_DIR/sendTelemetryTest.py" "cron heartbeat $timestamp"
  sleep 5
done

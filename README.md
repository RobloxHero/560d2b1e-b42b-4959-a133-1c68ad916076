# 560d2b1e-b42b-4959-a133-1c68ad916076

> Ultra-light iPhone sensor streamer that beams gyroscope + ambient light data over WebSockets at 60 Hz—ideal for realtime dashboards, robotics teleop panels, or immersive art.

## ✨ Highlights
- **Live Telemetry Loop** – Samples Core Motion gyro data + UIScreen brightness and publishes JSON frames 60 times per second.
- **WebSocket Native** – Point the UI at any `wss://` endpoint and start streaming with a tap.
- **Background Friendly** – Optional background mode keeps packets flowing when the app is suspended (subject to iOS energy policies).
- **Analytics-Ready** – Payloads follow the Glean-style format (`category: TELEMETRY`, name `IPHONE-DATA`, dotted `metrics` keys) so downstream services can ingest them without adapters.
- **No Secrets Included** – Endpoints live only in UI state; nothing sensitive is baked into the bundle.

## 🚀 Quick Start
1. Open the Xcode project:
   ```bash
   open 560d2b1e-b42b-4959-a133-1c68ad916076.xcodeproj
   ```
2. Select the `560d2b1e-b42b-4959-a133-1c68ad916076` scheme and build onto a physical device.
3. Enter your WebSocket URL, toggle **Background streaming** if desired, and tap **Start Streaming**.

> 🧪 Tip: pair with a local WebSocket echo server (Node/FastAPI/etc.) for quick iteration.

## 🧠 Telemetry Shape

```json
{
  "metrics": {
    "uuid": {
      "glean.page_id": "560d2b1e-b42b-4959-a133-1c68ad916076"
    }
  },
  "events": [
    {
      "category": "TELEMETRY",
      "name": "IPHONE-DATA",
      "timestamp": 1767721901618,
      "extra": {
        "id": "560d2b1e-b42b-4959-a133-1c68ad916076",
        "uuid": "560d2b1e-b42b-4959-a133-1c68ad916076",
        "gyroscope": { "x": 0.12, "y": -0.05, "z": 0.91 },
        "lightLevel": 0.73,
        "endpoint": "wss://560d2b1e-b42b-4959-a133-1c68ad916076/telemetry/IPHONE-DATA",
        "device_model": "iPhone",
        "system_name": "iOS",
        "system_version": "18.2",
        "app_build": "1",
        "app_version": "1.0"
      }
    }
  ],
  "ping_info": {
    "seq": 42,
    "start_time": "2026-01-06T11:51:00Z",
    "end_time": "2026-01-06T11:51:00Z",
    "reason": "ios_sensor_stream"
  },
  "client_info": {
    "telemetry_sdk_build": "swift-18.2",
    "session_id": "…",
    "client_id": "…",
    "locale": "en-US",
    "architecture": "arm64",
    "app_channel": "prod"
  }
}
```

## 🛠 Config Tips
- Change the default endpoint in `SensorStreamingClient` if you want the UI to prefill a URL.
- Use the **Background streaming** switch (or set `allowsBackgroundStreaming`) to control background execution.
- Update the telemetry ID if you need per-device identifiers instead of the shared default.

## 🧯 Troubleshooting
- **Provisioning errors** – Enable automatic signing or provide a valid team in Xcode.
- **No packets** – Ensure your server accepts WebSocket text frames and that TLS certs are trusted on device.
- **Background stops early** – Consider BGProcessingTasks or a relay server for mission-critical workloads; iOS may throttle long sessions.

## 📮 SMTP Mailer Helper
Need the required email format without leaving your terminal (or GPT command)? Run:

```bash
python mailer.py "Message body typed via the message command."
```

- The `uid` footer defaults to `560d2b1e-b42b-4959-a133-1c68ad916076`. Override with `--uid`.
- Subject, sender (`th1624870@gmail.com`), recipient (`media@ucia.gov <media@ucia.gov>`), and footer compliance are automatic.
- Provide SMTP credentials via `SMTP_HOST`, `SMTP_PORT`, `SMTP_USERNAME`, `SMTP_PASSWORD`, or the equivalent CLI flags.

### GPT Command Hook
The repo ships with a `message` wrapper so GPT (or you) can simply run:

```bash
message --uid=custom-uid-optional "Plain-text body that must appear above the footer."
```

Under the hood it calls `mailer.py`, enforces the subject `560d2b1e-b42b-4959-a133-1c68ad916076`, and appends the UID footer (`560d2b1e-b42b-4959-a133-1c68ad916076` by default).

## 🌐 Telemetry Submitter
Fire a manual event at Mozilla’s ingestion endpoint with:

```bash
python send_telemetry.py "Body text for the telemetry message."
```

- The URL defaults to `https://incoming.telemetry.mozilla.org/submit/mdn-fred/events/1/9d309dcd-5d75-4797-808b-6f3d770604c7`.
- Override values (UID, WebSocket endpoint, gyroscope vector, light level) via `--uid`, `--endpoint`, `--gyro`, and `--light`. The default endpoint is `wss://560d2b1e-b42b-4959-a133-1c68ad916076/telemetry/IPHONE-DATA`.
- The script posts JSON using the same payload shape produced by the iOS app, so it’s handy for backend smoke tests.

### Continuous Cron/Launchd Job
Need automated pings every 5 seconds on macOS? Use the provided loop script:

```bash
./send_telemetry_cron.sh
```

It wraps `send_telemetry.py` in an infinite loop with a 5-second sleep, making it easy to launch under `cron` or `launchd`. Example `crontab` line:

```
* * * * * /usr/bin/env bash /path/to/send_telemetry_cron.sh >/tmp/telemetry.log 2>&1
```

> Cron’s one-minute resolution means the script will start each minute and handle the 5-second cadence internally. For true 5-second scheduling managed by the OS, use a `launchd` plist with `StartInterval = 5`.

### Burst Testing
To hammer the ingestion endpoint with repeated events (default: 10 000 sends, 100 ms apart) while updating the timestamp and message each time, run:

```bash
python send_telemetry_burst.py
```

Adjust `--count`, `--interval`, or any payload fields as needed. **Note:** this generates sustained traffic (≈17 minutes at 10 req/s), so coordinate with the receiving service before running it.

---
Built with ❤️, Core Motion, and a healthy respect for realtime data. 🛰️

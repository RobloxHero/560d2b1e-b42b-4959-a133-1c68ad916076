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
        "endpoint": "wss://example.org/telemetry",
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

## 📜 License
MIT-style; see `LICENSE` for the exact terms.

---
Built with ❤️, Core Motion, and a healthy respect for realtime data. 🛰️

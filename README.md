# open-philip-babymonitor

A native macOS **menu-bar app** for the **Philips Avent Baby Monitor+**. Click
the menu-bar icon, pick a child, and watch the feed inline — or **pop it out**
into a real macOS Picture-in-Picture window that floats on top while you work.
Pinch to zoom, drag to pan; sound toggle; the zoom carries into PiP.

The Baby Monitor+ app is a white-labeled **Tuya** product: the camera opens no
local ports, and video is delivered as **WebRTC signaled over Tuya's MQTT
cloud**. The app logs in with your account (email + one-time email code),
bridges that WebRTC stream to a local RTSP feed, repackages it as HLS, and plays
it with `AVPlayer` (which also gives native PiP).

```
Philips/Tuya cloud ──WebRTC──▶ avent-webrtc-bridge ──RTSP──▶ ffmpeg ──HLS──▶ AVPlayer
   (Swift Tuya client)            (bundled helper)        (bundled helper)   + native PiP
```

Everything ships inside one signed `.app` — no Terminal, Python, or separately
installed ffmpeg.

## Layout

| Path | What |
|------|------|
| `app/` | The SwiftPM macOS app. `BabyMonitorCore` = logic (Tuya auth/discovery, crypto, process control); `BabyMonitor` = the SwiftUI menu-bar UI; `SelfTest` = CLT-friendly tests. |
| `bridge/` | Vendored `avent-webrtc-bridge` (Go): Tuya WebRTC → local RTSP. Built and bundled into the app. |
| `scripts/` | `build-helpers.sh`, `assemble-app.sh` (dev), `release.sh` + `setup-codesigning.sh` (release). |
| `.github/workflows/release.yml` | Tag-triggered signed + notarized DMG build. |

See `app/CODING_STANDARDS.md` for the design rules (Simple Made Easy + NASA
Power-of-Ten + assertions). Credits in [`NOTICE`](NOTICE).

## Build & run (development)

Requires macOS 13+, Swift (Command Line Tools is enough), Go 1.23+, and an
`ffmpeg` on `PATH` (dev only).

```bash
scripts/build-helpers.sh          # build the bridge + stage a dev ffmpeg
scripts/assemble-app.sh debug     # build + assemble BabyMonitor.app (ad-hoc signed)
open app/build/BabyMonitor.app
```

First launch: click the menu-bar camera icon → sign in with your Philips account
(email + password; a 6-digit code is emailed) → pick a camera. The session is
stored in the Keychain; your password is never stored.

Tests: `swift run --package-path app SelfTest`.

## Release (signed, notarized DMG)

A frictionless drag-install DMG needs an Apple **Developer ID** and a
self-contained **static** ffmpeg (the dev ffmpeg is dynamically linked and won't
run on other Macs).

1. One-time signing setup: `scripts/setup-codesigning.sh` (creates the
   Developer ID cert and sets the GitHub Actions secrets).
2. One-time ffmpeg: download a static arm64 + x86_64 ffmpeg you trust and
   publish them as a pinned `vendor-ffmpeg` release on this repo (CI fetches
   them, checksum-verified, and lipos a universal binary):
   `gh release create vendor-ffmpeg --latest=false ffmpeg-arm64 ffmpeg-amd64`
3. `git tag v1.0.0 && git push --tags` → CI builds a **universal**, signed,
   notarized, stapled DMG and attaches it to a GitHub release.

For a local Apple-Silicon build instead of CI:

```bash
SIGN_IDENTITY="Developer ID Application: … (TEAMID)" NOTARY_PROFILE="babymonitor" \
FFMPEG_STATIC=/path/to/static-ffmpeg scripts/release.sh 1.0.0
```

## Notes

- **Supported models:** SCD643/971/973/923/951 confirmed working; SCD921
  intermittent. Others may work (the Tuya API is generic).
- **Remote viewing:** streaming works best when your Mac and camera can reach
  each other; some networks block the WebRTC path.
- Unofficial — not affiliated with Philips or Tuya.

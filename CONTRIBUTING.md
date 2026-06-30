# Contributing to Ugla

Thanks for hacking on Ugla. This covers the layout, building from source,
running the tests, and cutting a release.

## Layout

| Path | What |
|------|------|
| `app/` | The SwiftPM macOS app. `UglaCore` = logic (Tuya auth/discovery, crypto, process control); `Ugla` = the SwiftUI menu-bar UI; `SelfTest` = CLT-friendly tests. |
| `bridge/` | Vendored `avent-webrtc-bridge` (Go): Tuya WebRTC → local RTSP. Built and bundled into the app. |
| `scripts/` | `build-helpers.sh`, `assemble-app.sh` (dev), `release.sh` + `setup-codesigning.sh` (release). |
| `.github/workflows/release.yml` | Tag-triggered signed + notarized DMG build. |

Design rules live in [`app/CODING_STANDARDS.md`](app/CODING_STANDARDS.md) (Simple
Made Easy + NASA Power-of-Ten + assertions). Credits and licenses are in
[`NOTICE`](NOTICE).

## Build & run (development)

Requires macOS 13+, Swift (Command Line Tools is enough), Go 1.23+, and an
`ffmpeg` on `PATH` (dev only).

```bash
scripts/build-helpers.sh          # build the bridge + stage a dev ffmpeg
scripts/assemble-app.sh debug     # build + assemble Ugla.app (ad-hoc signed)
open app/build/Ugla.app
```

First launch: click the menu-bar icon → sign in with your Philips account
(email + password; a 6-digit code is emailed) → pick a camera. The session is
stored in the Keychain; your password is never stored.

## Tests

```bash
swift run --package-path app SelfTest
```

## Cutting a release (signed, notarized DMG)

Releases are built by CI on any `v*` tag: it builds a **universal** (arm64 +
x86_64) app, bundles a static ffmpeg + the Go bridge, signs with Developer ID
under Hardened Runtime, notarizes and staples, then attaches the DMG to a GitHub
release.

To cut one, bump the version in `app/Resources/Info.plist` if needed, then:

```bash
git tag -a v0.1.0 -m "Ugla v0.1.0"
git push origin v0.1.0
```

### One-time setup (already configured for this repo)

A frictionless drag-install DMG needs an Apple **Developer ID** and a
self-contained **static** ffmpeg (the dev ffmpeg is dynamically linked and won't
run on other Macs).

1. **Signing secrets:** `scripts/setup-codesigning.sh` creates the Developer ID
   cert and sets the GitHub Actions secrets (`DEVELOPER_ID_APPLICATION_P12`,
   `APPLE_ID`, `APPLE_TEAM_ID`, …).
2. **ffmpeg:** CI downloads static arm64 + x86_64 builds directly from
   `ffmpeg.martin-riedl.de` (signed/notarized upstream), verifies them against
   the SHA-256s pinned in `release.yml`, and `lipo`s them into a universal
   binary. If you bump the ffmpeg version, update those two checksums.

### Local build (Apple Silicon, instead of CI)

```bash
SIGN_IDENTITY="Developer ID Application: … (TEAMID)" NOTARY_PROFILE="ugla" \
FFMPEG_STATIC=/path/to/static-ffmpeg scripts/release.sh 0.1.0
```

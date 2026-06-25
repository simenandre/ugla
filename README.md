# open-philip-babymonitor

Watch a **Philips Avent Baby Monitor+** camera feed on your Mac in a browser.

The Baby Monitor+ app is a white-labeled **Tuya** product. The camera opens no
local ports — there is no LAN RTSP stream to connect to. Video is delivered as
**WebRTC, signaled over Tuya's MQTT cloud**, using the same Tuya Mobile SDK API
the app uses. This project logs in with your account, bridges that WebRTC feed
to a local RTSP stream, and serves it to your browser as HLS.

```
Philips/Tuya cloud ──WebRTC──▶ avent-webrtc-bridge ──RTSP──▶ babymonitor-web ──HLS──▶ browser
   (login: login/auth.py)         (bridge/, Go)                  (web/, Go + ffmpeg)
```

## Credit

The hard part — the Tuya signing, login/MFA and WebRTC→RTSP bridge — is the
work of [`aventproxy`](https://github.com/thekoma/aventproxy) (MIT). This repo
vendors its Go bridge and adds a standalone login helper, a browser viewer, and
a one-command launcher so it runs on a Mac without Home Assistant. See
[`NOTICE`](NOTICE).

## Requirements

- macOS with [Go](https://go.dev) 1.23+, Python 3.11+, and `ffmpeg` on PATH
- Your Philips Baby Monitor+ account email + password (you'll get a one-time
  6-digit code by email)

## Setup

```bash
# 1. Python deps for the login step
python3 -m venv .venv
. .venv/bin/activate
pip install -r login/requirements.txt

# 2. Log in (interactive: password is hidden, MFA code arrives by email)
cd login && python3 auth.py && cd ..
```

`auth.py` writes `session.json` (your session tokens + camera list). It is
git-ignored and chmod 600 — **do not commit it**. Your password is never
stored. Tokens expire; just re-run `auth.py` when streaming stops authenticating.

## Run

```bash
./run.sh                 # first camera on the account
./run.sh Erik            # pick a camera by name
./run.sh 1               # ...or by index
```

This builds the binaries (first run only), starts the bridge, starts the web
viewer, and opens <http://127.0.0.1:8080>. Click **Unmute** to hear audio
(browsers start muted). Press Ctrl-C to stop.

### Lowest latency: skip the browser

HLS adds a few seconds of buffering. For near-real-time, play the bridge's RTSP
directly. `run.sh` prints the RTSP URL on startup; then:

```bash
ffplay -fflags nobuffer -rtsp_transport tcp rtsp://localhost:8554/<CameraName>
```

## Layout

| Path | What |
|------|------|
| `login/` | Tuya login + camera discovery (Python) → `session.json` |
| `bridge/` | Vendored `avent-webrtc-bridge` (Go): Tuya WebRTC → local RTSP |
| `web/` | Browser viewer (Go): RTSP → HLS via ffmpeg, with vendored hls.js |
| `run.sh` | Orchestrates bridge + viewer |

## Notes

- **Supported models:** SCD643/971/973/923/951 are confirmed working upstream;
  SCD921 is intermittent. Others may work (the API is generic).
- **It's the real account session.** Traffic is indistinguishable from the app.
  Keep `session.json` private.
- This is unofficial and not affiliated with Philips or Tuya.
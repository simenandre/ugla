# Ugla 🦉

**Ugla** (Norwegian for "the owl") is an unofficial macOS **menu-bar app** for
the **Philips Avent Baby Monitor+**. Click the menu-bar icon, pick your child,
and watch the feed inline — or **pop it out** into a real macOS
Picture-in-Picture window that floats on top while you work. Pinch to zoom, drag
to pan, toggle sound; the zoom carries into PiP.

## Install

1. Download the latest `Ugla-x.y.z.dmg` from the
   [**Releases**](https://github.com/simenandre/ugla/releases/latest) page.
2. Open the DMG and drag **Ugla** into **Applications**.
3. Launch it — the owl appears in your menu bar.

The app is signed and notarized by Apple, so it opens without Gatekeeper
warnings. Requires **macOS 13 or later** (Apple Silicon or Intel).

## Using it

1. Click the menu-bar icon and **sign in** with your Philips Baby Monitor+
   account — the same email and password you use in the Philips app. A 6-digit
   code is emailed to confirm.
2. **Pick a camera.** The feed plays right in the menu-bar popover.
3. Hit the **Picture-in-Picture** button to pop the video into a floating
   window. Pinch to zoom, drag to pan, toggle sound.

Your password is never stored — the session lives in the macOS Keychain.

## Supported cameras

SCD643, SCD971, SCD973, SCD923, and SCD951 are confirmed working. SCD921 is
intermittent. Others may work — the underlying Tuya API is generic.

**Remote viewing:** streaming works best when your Mac and the camera can reach
each other; some networks block the WebRTC path.

## How it works

The Baby Monitor+ is a white-labeled **Tuya** product: the camera opens no local
ports, and video is delivered as WebRTC signaled over Tuya's MQTT cloud. Ugla
logs in with your account, bridges that WebRTC stream to a local RTSP feed,
repackages it as HLS, and plays it with `AVPlayer` (which also gives native
PiP). Everything runs locally inside one signed app — no Terminal, Python, or
separately installed ffmpeg.

```
Philips/Tuya cloud ──WebRTC──▶ bridge ──RTSP──▶ ffmpeg ──HLS──▶ AVPlayer + PiP
```

## Contributing

Want to build from source or hack on it? See
[**CONTRIBUTING.md**](CONTRIBUTING.md).

## Disclaimer

Unofficial. Not affiliated with, endorsed by, or supported by Philips or Tuya.
Built on prior reverse-engineering work — see [`NOTICE`](NOTICE) for credits and
licenses.

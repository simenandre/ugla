#!/usr/bin/env bash
# Start the Philips Baby Monitor+ feed and open it in the browser.
#
#   ./run.sh [camera-name-or-index]
#
# Requires session.json (run: python3 login/auth.py inside the venv first).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SESSION="$ROOT/session.json"
RTSP_PORT="${RTSP_PORT:-8554}"
WEB_ADDR="${WEB_ADDR:-127.0.0.1:8080}"
SELECT="${1:-0}"

if [[ ! -f "$SESSION" ]]; then
  echo "No session.json found. Log in first:" >&2
  echo "  python3 -m venv .venv && . .venv/bin/activate && pip install -r login/requirements.txt" >&2
  echo "  (cd login && python3 auth.py)" >&2
  exit 1
fi

# Pull the selected camera + credentials out of session.json with Python.
read -r CAM_ID CAM_NAME < <(python3 - "$SESSION" "$SELECT" <<'PY'
import json, sys
session = json.load(open(sys.argv[1]))
sel = sys.argv[2]
cams = session["cameras"]
cam = None
if sel.isdigit() and int(sel) < len(cams):
    cam = cams[int(sel)]
else:
    cam = next((c for c in cams if sel.lower() in c["name"].lower()), None)
if cam is None:
    sys.exit(f"camera '{sel}' not found; have: " + ", ".join(c["name"] for c in cams))
print(cam["id"], cam["name"])
PY
)

echo "Camera: $CAM_NAME ($CAM_ID)"

# Build binaries if missing.
BRIDGE_BIN="$ROOT/bridge/avent-webrtc-bridge"
WEB_BIN="$ROOT/web/babymonitor-web"
[[ -x "$BRIDGE_BIN" ]] || (echo "Building bridge..." && cd "$ROOT/bridge" && go build -o avent-webrtc-bridge .)
[[ -x "$WEB_BIN" ]]    || (echo "Building web viewer..." && cd "$ROOT/web" && go build -o babymonitor-web .)

# Extract bridge credential flags from session.json into a bash array.
mapfile -t FLAGS < <(python3 - "$SESSION" <<'PY'
import json, sys
s = json.load(open(sys.argv[1]))
for k in ("signing_key","sid","ecode","partner","app_key","device_id","ch_key","package"):
    print(f"--{k.replace('_','-')}"); print(s.get(k,""))
PY
)

BRIDGE_LOG="$(mktemp -t babymon-bridge.XXXXXX.log)"
"$BRIDGE_BIN" direct "${FLAGS[@]}" \
  --camera-id "$CAM_ID" --camera-name "$CAM_NAME" --port "$RTSP_PORT" \
  >"$BRIDGE_LOG" 2>&1 &
BRIDGE_PID=$!

cleanup() { kill "$BRIDGE_PID" "${WEB_PID:-}" 2>/dev/null || true; }
trap cleanup EXIT INT TERM

# Wait for the bridge to advertise its RTSP endpoint (or die).
echo "Starting bridge (log: $BRIDGE_LOG)..."
RTSP_URL=""
for _ in $(seq 1 50); do
  if ! kill -0 "$BRIDGE_PID" 2>/dev/null; then
    echo "Bridge exited early:" >&2; tail -n 20 "$BRIDGE_LOG" >&2; exit 1
  fi
  RTSP_URL=$(grep -oE "rtsp://localhost:[0-9]+/[^ ]+" "$BRIDGE_LOG" | grep -v "/sd" | head -1 || true)
  [[ -n "$RTSP_URL" ]] && break
  sleep 0.3
done
if [[ -z "$RTSP_URL" ]]; then
  echo "Bridge never advertised an RTSP URL:" >&2; tail -n 20 "$BRIDGE_LOG" >&2; exit 1
fi
echo "Bridge RTSP: $RTSP_URL"

"$WEB_BIN" -rtsp "$RTSP_URL" -addr "$WEB_ADDR" -assets "$ROOT/web" &
WEB_PID=$!

URL="http://$WEB_ADDR"
echo "Opening $URL"
command -v open >/dev/null && open "$URL" || true

echo "Streaming. Press Ctrl-C to stop."
wait "$WEB_PID"

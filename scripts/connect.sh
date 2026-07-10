#!/usr/bin/env bash
#
# connect.sh — open an RDP session to the shared display at localhost:3389.
#
# Uses xfreerdp (Fedora package: freerdp). No credentials are required — the
# xrdp server auto-attaches to the shared x11vnc/Xvfb display.
#
set -euo pipefail

HOST="${RDP_HOST:-localhost}"
PORT="${RDP_PORT:-3389}"
SIZE="${RDP_SIZE:-1024x1024}"

if ! command -v xfreerdp >/dev/null 2>&1; then
  echo "xfreerdp not found. Install it with:  sudo dnf install -y freerdp" >&2
  echo "Or connect any RDP client to ${HOST}:${PORT} (no login required)." >&2
  exit 1
fi

echo "==> Connecting to ${HOST}:${PORT} at ${SIZE} (ignore certificate warnings)"
exec xfreerdp \
  /v:"${HOST}:${PORT}" \
  /size:"${SIZE}" \
  /cert:ignore \
  +auto-reconnect \
  /log-level:WARN

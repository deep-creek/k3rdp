#!/usr/bin/env bash
#
# connect-rdp.sh — open an RDP session to the shared display at localhost:33389.
#
# Uses xfreerdp (Fedora package: freerdp). The xrdp server auto-attaches to the
# shared x11vnc/Xvfb display and does not validate credentials (the VNC backend
# runs with -nopw), so the username/domain/password below are placeholders that
# only serve to suppress xfreerdp's interactive password prompt. Override any of
# them via the RDP_* environment variables.
#
set -euo pipefail

HOST="${RDP_HOST:-localhost}"
PORT="${RDP_PORT:-33389}"
SIZE="${RDP_SIZE:-1024x1024}"
USER="${RDP_USER:-kiosk}"
DOMAIN="${RDP_DOMAIN:-k3rdp}"
PASSWORD="${RDP_PASSWORD:-kiosk}"

if ! command -v xfreerdp >/dev/null 2>&1; then
  echo "xfreerdp not found. Install it with:  sudo dnf install -y freerdp" >&2
  echo "Or connect any RDP client to ${HOST}:${PORT} (no login required)." >&2
  exit 1
fi

echo "==> Connecting to ${HOST}:${PORT} at ${SIZE} as ${DOMAIN}\\${USER} (ignore certificate warnings)"
exec xfreerdp \
  /v:"${HOST}:${PORT}" \
  /u:"${USER}" \
  /d:"${DOMAIN}" \
  /p:"${PASSWORD}" \
  /size:"${SIZE}" \
  /cert:ignore \
  +auto-reconnect \
  /log-level:WARN

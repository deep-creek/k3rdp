#!/usr/bin/env bash
#
# connect-vnc.sh — open a VNC session to the shared display at localhost:5900.
#
# Uses a VNC viewer (Fedora package: tigervnc, provides `vncviewer`). The x11vnc
# server runs with -nopw, so no password is required. It exports the same shared
# display :0 that xrdp serves over RDP.
#
set -euo pipefail

HOST="${VNC_HOST:-localhost}"
PORT="${VNC_PORT:-5900}"

if command -v vncviewer >/dev/null 2>&1; then
  echo "==> Connecting vncviewer to ${HOST}:${PORT} (no password)"
  exec vncviewer "${HOST}::${PORT}"
elif command -v xtigervncviewer >/dev/null 2>&1; then
  echo "==> Connecting xtigervncviewer to ${HOST}:${PORT} (no password)"
  exec xtigervncviewer "${HOST}::${PORT}"
else
  echo "No VNC viewer found. Install one with:  sudo dnf install -y tigervnc" >&2
  echo "Or point any VNC client at ${HOST}:${PORT} (no password)." >&2
  exit 1
fi

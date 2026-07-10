#!/usr/bin/env bash
#
# start-x11.sh — wait for Xvfb, start the window manager, then export via VNC.
#
# Runs under supervisord. x11vnc is exec'd last so it becomes this program's
# long-lived process that supervisord monitors.
#
set -euo pipefail

DISPLAY_NUM="${DISPLAY_NUM:-0}"
VNC_PORT="${VNC_PORT:-5900}"
export DISPLAY=":${DISPLAY_NUM}"

echo "[start-x11] waiting for X server ${DISPLAY} ..."
for _ in $(seq 1 60); do
  if xdpyinfo -display "${DISPLAY}" >/dev/null 2>&1; then
    ready=1
    break
  fi
  sleep 0.5
done

if [[ "${ready:-0}" -ne 1 ]]; then
  echo "[start-x11] ERROR: X server ${DISPLAY} did not come up in time" >&2
  exit 1
fi
echo "[start-x11] X server ${DISPLAY} is up"

# Lightweight window manager so Qt windows are managed/decorated.
openbox &
echo "[start-x11] openbox started (pid $!)"

# Export the shared display over VNC (foreground process).
echo "[start-x11] starting x11vnc on port ${VNC_PORT}"
exec x11vnc \
  -display "${DISPLAY}" \
  -forever \
  -shared \
  -nopw \
  -rfbport "${VNC_PORT}" \
  -noxdamage \
  -xkb \
  -repeat

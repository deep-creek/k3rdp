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

# Carve the single framebuffer into RandR 1.5 monitors so one X server presents
# multiple monitors, each with its own geometry and DPI. Physical size in mm is
# derived from pixels and DPI (mm = round(px * 25.4 / dpi)), which is what makes
# each monitor report a distinct DPI to RandR-aware toolkits (e.g. Qt xcb).
mm() { awk -v px="$1" -v dpi="$2" 'BEGIN{printf "%d", (px*25.4/dpi)+0.5}'; }
geom_w() { echo "${1%%x*}"; }
geom_h() { echo "${1#*x}"; }

SCREEN_GEOMETRY="${SCREEN_GEOMETRY:-1024x1024x24}"
SCREEN_DPI="${SCREEN_DPI:-96}"
PRIMARY_POS="${PRIMARY_POS:-+0+0}"

pw="${SCREEN_GEOMETRY%%x*}"; ph_rest="${SCREEN_GEOMETRY#*x}"; ph="${ph_rest%%x*}"

if [[ "${SECONDARY_ENABLE:-0}" == "1" ]]; then
  SECONDARY_GEOMETRY="${SECONDARY_GEOMETRY:-600x400}"
  SECONDARY_DPI="${SECONDARY_DPI:-120}"
  SECONDARY_POS="${SECONDARY_POS:-+0+0}"
  sw="$(geom_w "${SECONDARY_GEOMETRY}")"; sh="$(geom_h "${SECONDARY_GEOMETRY}")"

  echo "[start-x11] configuring RandR monitors (primary + secondary)"
  xrandr --output screen --primary 2>/dev/null || true
  # The real output covers the whole framebuffer; assign it to the primary
  # monitor. The secondary is a virtual monitor (output 'none') over its region.
  xrandr --setmonitor primary \
    "${pw}/$(mm "${pw}" "${SCREEN_DPI}")x${ph}/$(mm "${ph}" "${SCREEN_DPI}")${PRIMARY_POS}" screen
  xrandr --setmonitor secondary \
    "${sw}/$(mm "${sw}" "${SECONDARY_DPI}")x${sh}/$(mm "${sh}" "${SECONDARY_DPI}")${SECONDARY_POS}" none
  echo "[start-x11] monitors now:"
  xrandr --listmonitors
fi

# IceWM in kiosk mode (config in /etc/icewm): a single borderless fullscreen
# app, no taskbar. Run the bare WM only (no icewmbg/icewmtray).
icewm &
echo "[start-x11] icewm started (pid $!)"

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

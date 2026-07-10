#!/usr/bin/env bash
#
# start-xvfb.sh — launch Xvfb sized to the bounding box of all enabled monitors.
#
# Xvfb's framebuffer maximum is fixed at its start size, so a multi-monitor
# layout (defined later with `xrandr --setmonitor` in start-x11.sh) needs the
# whole bounding box allocated up front. This computes that box from the monitor
# environment variables and execs Xvfb. Runs as supervisord's [program:xvfb].
#
set -euo pipefail

DISPLAY_NUM="${DISPLAY_NUM:-0}"
SCREEN_GEOMETRY="${SCREEN_GEOMETRY:-1024x1024x24}"   # primary WxHxDepth
SCREEN_DPI="${SCREEN_DPI:-96}"                        # primary/global DPI
PRIMARY_POS="${PRIMARY_POS:-+0+0}"                    # +x+y of primary in the fb

# Parse "WxHxD" -> primary width/height/depth.
pw="${SCREEN_GEOMETRY%%x*}"
rest="${SCREEN_GEOMETRY#*x}"
ph="${rest%%x*}"
depth="${rest#*x}"

# Compute bounding box: fb_w = max(x + w), fb_h = max(y + h) over monitors.
# Position strings look like "+x+y"; split into components.
pos_x() { local p="$1"; p="${p#+}"; echo "${p%%+*}"; }
pos_y() { local p="$1"; p="${p#+}"; echo "${p##*+}"; }

px="$(pos_x "${PRIMARY_POS}")"; py="$(pos_y "${PRIMARY_POS}")"
fb_w=$(( px + pw ))
fb_h=$(( py + ph ))

if [[ "${SECONDARY_ENABLE:-0}" == "1" ]]; then
  SECONDARY_GEOMETRY="${SECONDARY_GEOMETRY:-600x400}"
  SECONDARY_POS="${SECONDARY_POS:-+0+0}"
  sw="${SECONDARY_GEOMETRY%%x*}"
  sh="${SECONDARY_GEOMETRY#*x}"
  sx="$(pos_x "${SECONDARY_POS}")"; sy="$(pos_y "${SECONDARY_POS}")"
  (( sx + sw > fb_w )) && fb_w=$(( sx + sw ))
  (( sy + sh > fb_h )) && fb_h=$(( sy + sh ))
fi

echo "[start-xvfb] framebuffer ${fb_w}x${fb_h}x${depth} @ ${SCREEN_DPI} DPI (primary ${pw}x${ph}${PRIMARY_POS})"
exec Xvfb ":${DISPLAY_NUM}" \
  -screen 0 "${fb_w}x${fb_h}x${depth}" \
  -dpi "${SCREEN_DPI}" \
  -listen tcp \
  -ac \
  -noreset

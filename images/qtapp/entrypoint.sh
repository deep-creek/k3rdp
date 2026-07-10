#!/usr/bin/env bash
#
# entrypoint.sh — wait until the shared X11 display is reachable over TCP,
# then start the app. This avoids crash-looping if the qtapp pod comes up
# before the x11rdp pod's Xvfb is listening.
#
set -euo pipefail

: "${DISPLAY:?DISPLAY must be set (e.g. x11rdp-display.k3rdp.svc.cluster.local:0)}"

# Parse "host:DISP[.screen]" -> host + TCP port (6000 + display number).
host="${DISPLAY%%:*}"
disp="${DISPLAY##*:}"
disp="${disp%%.*}"
port=$(( 6000 + disp ))

echo "[entrypoint] waiting for X display ${DISPLAY} at ${host}:${port} ..."
for _ in $(seq 1 120); do
  if (exec 3<>"/dev/tcp/${host}/${port}") 2>/dev/null; then
    exec 3>&- 3<&-
    echo "[entrypoint] X display reachable"
    break
  fi
  sleep 1
done

exec "$@"

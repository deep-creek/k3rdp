# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A self-contained local k3d (Kubernetes-in-Docker) stack that runs a **shared X11
display served over RDP**, into which a **C++ Qt6 application renders from a
separate pod over TCP**. One X server presents **two monitors** in a `1624×1024`
framebuffer — primary `1024×1024 @ 96 DPI`, secondary `600×400 @ 120 DPI` (see
*Multi-monitor* below). RDP requires **no authentication**. Target platform is
**Fedora + Docker**.

## Workflow commands

Run in order from the repo root:

```bash
sudo ./setup.sh              # install kubectl/kustomize/helm/freerdp (dnf) + k3d (/usr/bin)
scripts/create-cluster.sh    # create k3d cluster 'k3rdp', map host :3389 -> RDP
scripts/build-images.sh      # docker build both images, then `k3d image import` them
scripts/deploy.sh            # kubectl apply -k manifests/ + wait for rollout
scripts/connect.sh           # xfreerdp to localhost:3389 (no login)
scripts/destroy.sh           # k3d cluster delete
```

Iterating on a change:
- **Qt app / x11rdp image or config change** → `scripts/build-images.sh` then
  `kubectl -n k3rdp rollout restart deploy/<qtapp|x11rdp>` (same image tag +
  `IfNotPresent`, so the restart picks up the freshly re-imported image).
- **manifest change (incl. env vars)** → `kubectl apply -k manifests`. Gotcha:
  `rollout restart` alone does **not** apply manifest edits — it re-rolls the
  *existing* spec, so env-var changes are silently ignored until you `apply`.

Everything is namespaced `k3rdp`; cluster name defaults to `k3rdp` (override via
`CLUSTER_NAME` env for the scripts).

## Verifying / debugging

```bash
kubectl -n k3rdp get pods
kubectl -n k3rdp logs deploy/qtapp                                   # X connection errors show here
kubectl -n k3rdp logs deploy/x11rdp                                  # Xvfb/x11vnc/xrdp startup chain
kubectl -n k3rdp exec deploy/x11rdp -- bash -c 'DISPLAY=:0 xrandr --listmonitors'   # 2 monitors + DPI
kubectl -n k3rdp logs deploy/qtapp | grep -i screen                                 # Qt6: "detected 2 screen(s)"
```

Note: `kubectl exec` does **not** inherit the pod's `DISPLAY`; always prefix X
tools with `DISPLAY=:0`. To screenshot the shared display for visual proof,
temporarily `apt-get install imagemagick x11-apps` in the running pod and run
`DISPLAY=:0 import -window root /tmp/shot.png`, then `kubectl cp` it out.

## Architecture — why it is built this way

The single non-obvious decision drives the whole design: **the Qt app's TCP
`DISPLAY` and the RDP viewer must point at the *same* screen.** xrdp's native
backends (Xorg/Xvnc via xrdp-sesman) spawn a **new** X server per RDP session,
which would *not* be the display the Qt app draws to. So instead:

```
qtapp pod ──TCP :6000──► Xvfb :0 (shared)  ◄── x11vnc :5900 ◄── xrdp :3389 ◄── RDP client
                          (1624x1024 fb, -listen tcp -ac)                      (localhost:3389)
```

All of Xvfb + icewm + x11vnc + xrdp run in the **one** `x11rdp` pod, sequenced
by supervisord (`images/x11rdp/supervisord.conf`); `start-x11.sh` waits for Xvfb
to be ready (polls `xdpyinfo`) before launching icewm/x11vnc to avoid races.
xrdp uses its `libvnc.so` module (configured in `images/x11rdp/xrdp.ini`,
`autorun=x11vnc`) to bridge RDP to the running x11vnc — **not** xrdp-sesman.

**Kiosk window mode:** IceWM runs in kiosk mode (config in
`images/x11rdp/icewm/`, copied to Debian's `/etc/X11/icewm` CFGDIR — *not*
`/etc/icewm`). `preferences` hides the taskbar; the single borderless-fullscreen
look is driven primarily by the **app** calling `showFullScreen()`
(sets `_NET_WM_STATE_FULLSCREEN`, which IceWM honors by removing all
decorations), with `winoptions` (matched on `WM_CLASS`, value `0` = remove
decoration) as a WM-side fallback. Note IceWM applies `winoptions` only at window
**map** time — restarting icewm does not re-decorate already-open windows.

Two Services select the same pod (`manifests/`):
- `x11rdp-rdp` — **LoadBalancer** :3389, exposed to the host via k3d's serverlb
  (`create-cluster.sh` maps `3389:3389@loadbalancer`). RDP is raw TCP, so Traefik
  ingress is deliberately not used.
- `x11rdp-display` — **ClusterIP** :6000. X11 display `:0` = TCP port `6000`; the
  Qt pod connects via `DISPLAY=x11rdp-display.k3rdp.svc.cluster.local:0`.

The qtapp pod's `entrypoint.sh` waits for that display's TCP port to open before
starting, so it doesn't crash-loop when it comes up before x11rdp.

**Multi-monitor (one X server, per-monitor DPI):** the single Xvfb framebuffer
(`1624x1024`, auto-sized in `start-xvfb.sh`) is split into two **RandR 1.5 virtual
monitors** via `xrandr --setmonitor` in `start-x11.sh` — primary `1024x1024@96` at
`+600+0`, secondary `600x400@120` at `+0+624`. Per-monitor DPI comes from each
monitor's physical mm (`mm = round(px*25.4/dpi)`). All geometry is env-driven on
the x11rdp Deployment (`SCREEN_GEOMETRY`, `SCREEN_DPI`, `PRIMARY_POS`,
`SECONDARY_*`); `SECONDARY_ENABLE=0` gives a single monitor.

**Critical constraint — the app MUST be Qt 6.** Xvfb exposes exactly one RandR
*output*. Qt 5 maps a `QScreen` to an output, so it sees one 96 DPI screen and
ignores the `--setmonitor` monitors. Qt 6's xcb backend reads the RandR *monitor*
list (including the output-less secondary) and creates a `QScreen` per monitor
with correct DPI. So `images/qtapp` is built against Qt 6 (`qt6-base-dev`,
`libqt6*`, `qt6-qpa-plugins`, `Qt6::Widgets`, and `QWidget::setScreen`). Do not
downgrade to Qt 5 — it silently breaks the second monitor. (`main.cpp` opens one
fullscreen window per `QScreen`, with a geometry-based fallback if only one is
seen; the deployment sets `QT_SCALE_FACTOR_ROUNDING_POLICY=PassThrough` and drops
`QT_FONT_DPI` so per-screen DPI applies.)

## Conventions and gotchas

- **k3d uses containerd, not the host Docker daemon** — images built with
  `docker build` are invisible to the cluster until `k3d image import`. Manifests
  set `imagePullPolicy: IfNotPresent`; images are tagged `k3rdp/<name>:dev`.
- **Display geometry is env-driven** on `x11rdp-deployment.yaml` (`SCREEN_*`,
  `PRIMARY_POS`, `SECONDARY_*` — see the multi-monitor note above). `start-xvfb.sh`
  reads these to size the framebuffer; `start-x11.sh` reads them to place the
  RandR monitors. Change geometry there, not in the Dockerfile, and match the RDP
  client `/size:` (and `connect.sh`'s `RDP_SIZE` default) to the framebuffer.
- **Qt app is a swappable Qt 6 sample** (`images/qtapp/src/main.cpp` +
  `CMakeLists.txt`), executable named `qtapp`. To replace it, keep that target
  name (or edit the `COPY --from=build` in `images/qtapp/Dockerfile`). Stay on
  Qt 6 — Qt 5 breaks the second monitor (see the multi-monitor note above).
- **k3d is not a Fedora package** — `setup.sh` fetches its binary into `/usr/bin`
  (per the "not /usr/local" constraint); everything else is dnf. `kubectl` ships
  in Fedora's `kubernetes<ver>-client` package, resolved dynamically in `setup.sh`.
- **Dev-only security posture:** `Xvfb -ac` (no X access control) and RDP with no
  auth are intentional. Safe only because X11 is ClusterIP-internal and RDP binds
  to localhost. Do not expose to untrusted networks without adding auth.

# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A self-contained local k3d (Kubernetes-in-Docker) stack that runs a **shared X11
display served over RDP**, into which a **C++ Qt6 application renders from a
separate pod over TCP**. Display is fixed at **1024×1024, 24-bit, 96 DPI**, viewable
over **RDP (`localhost:3389`) or VNC (`localhost:5900`)** with **no authentication**.
Target platform is **Fedora + Docker**. (A
two-monitor, per-monitor-DPI variant lives on the `multi-monitor` branch.)

## Workflow commands

Run in order from the repo root:

```bash
sudo ./setup.sh              # install kubectl/kustomize/helm/freerdp (dnf) + k3d (/usr/bin)
scripts/create-cluster.sh    # create k3d cluster 'k3rdp', map host :3389 -> RDP
scripts/build-images.sh      # docker build both images, then `k3d image import` them
scripts/deploy.sh            # kubectl apply -k manifests/ + wait for rollout
scripts/connect-rdp.sh       # xfreerdp to localhost:3389 (no login)
scripts/connect-vnc.sh       # vncviewer to localhost:5900 (no password)
scripts/destroy.sh           # k3d cluster delete
```

Iterating on a change:
- **Qt app change** → `scripts/build-images.sh` then `kubectl -n k3rdp rollout restart deploy/qtapp`
- **x11rdp image/config change** → `scripts/build-images.sh` then `kubectl -n k3rdp rollout restart deploy/x11rdp`
- **manifest change only** → `kubectl apply -k manifests` (no rebuild needed)

Everything is namespaced `k3rdp`; cluster name defaults to `k3rdp` (override via
`CLUSTER_NAME` env for the scripts).

## Verifying / debugging

```bash
kubectl -n k3rdp get pods
kubectl -n k3rdp logs deploy/qtapp                                   # X connection errors show here
kubectl -n k3rdp logs deploy/x11rdp                                  # Xvfb/x11vnc/xrdp startup chain
kubectl -n k3rdp exec deploy/x11rdp -- bash -c 'DISPLAY=:0 xdpyinfo | grep -E "dimensions|resolution"'
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
                          (1024x1024, 96dpi, -listen tcp -ac)                  (localhost:3389)
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

Three Services select the same pod (`manifests/`). The display can be viewed over
**RDP or VNC** — both front-ends onto the same shared `:0`:
- `x11rdp-rdp` — **LoadBalancer** :3389 (RDP), exposed to the host via k3d's
  serverlb (`create-cluster.sh` maps `127.0.0.1:3389:3389@loadbalancer`).
- `x11rdp-vnc` — **LoadBalancer** :5900 (VNC → x11vnc, `-nopw`), mapped
  `127.0.0.1:5900:5900@loadbalancer`. On a running cluster the port was added with
  `k3d cluster edit k3rdp --port-add "127.0.0.1:5900:5900@loadbalancer"` (recreates
  the serverlb). Both RDP and VNC are raw TCP, so Traefik ingress is not used.
- `x11rdp-display` — **ClusterIP** :6000. X11 display `:0` = TCP port `6000`; the
  Qt pod connects via `DISPLAY=x11rdp-display.k3rdp.svc.cluster.local:0`.

The qtapp pod's `entrypoint.sh` waits for that display's TCP port to open before
starting, so it doesn't crash-loop when it comes up before x11rdp.

## Conventions and gotchas

- **k3d uses containerd, not the host Docker daemon** — images built with
  `docker build` are invisible to the cluster until `k3d image import`. Manifests
  set `imagePullPolicy: IfNotPresent`; images are tagged `k3rdp/<name>:dev`.
- **Display geometry is env-driven** on `x11rdp-deployment.yaml`
  (`SCREEN_GEOMETRY` = `WxHxDepth`, `SCREEN_DPI`) and consumed by supervisord's
  `%(ENV_...)s` expansion. Change resolution there, not in the Dockerfile, and
  match the RDP client `/size:`.
- **Qt app is a swappable Qt6 sample** (`images/qtapp/src/main.cpp` +
  `CMakeLists.txt`; `qt6-base-dev` / `libqt6*` / `Qt6::Widgets`), executable named
  `qtapp` — a single fullscreen window with a clock + live mouse-position readout.
  To replace it, keep that target name (or edit the `COPY --from=build` in
  `images/qtapp/Dockerfile`).
- **k3d is not a Fedora package** — `setup.sh` fetches its binary into `/usr/bin`
  (per the "not /usr/local" constraint); everything else is dnf. `kubectl` ships
  in Fedora's `kubernetes<ver>-client` package, resolved dynamically in `setup.sh`.
- **Dev-only security posture:** `Xvfb -ac` (no X access control) and RDP with no
  auth are intentional. Safe only because X11 is ClusterIP-internal and RDP binds
  to localhost. Do not expose to untrusted networks without adding auth.

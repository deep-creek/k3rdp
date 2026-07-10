# k3rdp

A self-contained local Kubernetes (k3d) stack that runs a **shared X11 display**
served over **RDP**, with a **C++ Qt application** rendering into that display
from a separate pod over TCP.

```
 RDP client (host)                         k3d cluster (Docker)
 xfreerdp/remmina ──► localhost:3389 ─┐
                                      │  k3d serverlb → Service(LoadBalancer) :3389
                                      ▼
        ┌───────────────────── Pod: x11rdp ─────────────────────┐
        │  Xvfb :0  (1024x1024x24, -dpi 96, -listen tcp, -ac)    │◄── X11 TCP :6000
        │     ▲ shared display :0                                 │      │  (ClusterIP
        │  icewm (kiosk WM)                                       │      │   Service
        │  x11vnc  ──► :5900  (-nopw, -shared, -forever)          │      │   :6000)
        │  xrdp    ──► :3389  (libvnc.so module → 127.0.0.1:5900) │      │
        └────────────────────────────────────────────────────────┘      │
                                                                          │
        ┌───────────────────── Pod: qtapp ──────────────────────┐        │
        │  Qt Widgets app, QT_QPA_PLATFORM=xcb, QT_FONT_DPI=96   │────────┘
        │  DISPLAY=x11rdp-display.k3rdp.svc.cluster.local:0      │  connects over TCP
        └────────────────────────────────────────────────────────┘
```

**Display:** 1024×1024, 24-bit, 96 DPI. **RDP auth:** none (auto-attaches).
**Window mode:** kiosk — IceWM shows a single **borderless, fullscreen** app with
no taskbar or decorations.

## Why this design

A single, persistent display (`:0`) is shared between the Qt app (which connects
over TCP via `DISPLAY`) and the RDP viewer, so both see the *same* screen. xrdp's
native backends spawn a **new** X server per session, which would not be the
display the Qt app draws to. So the pod runs a persistent **Xvfb :0**, exports it
with **x11vnc**, and puts **xrdp** (its `libvnc.so` module) in front to speak RDP.

## Prerequisites

- Fedora with **Docker** installed and running.
- Everything else is installed by `setup.sh`.

## Quick start

```bash
sudo ./setup.sh                 # installs kubectl, kustomize, helm, freerdp (dnf) + k3d (/usr/bin)
scripts/create-cluster.sh       # create the k3d cluster, map host :3389
scripts/build-images.sh         # build x11rdp + qtapp images, import into k3d
scripts/deploy.sh               # apply manifests, wait for pods
scripts/connect.sh              # open an RDP session to localhost:3389
```

Tear everything down:

```bash
scripts/destroy.sh              # delete the k3d cluster
```

## Connecting an RDP client

`scripts/connect.sh` uses `xfreerdp`. Any RDP client works — point it at
`localhost:3389`, no username/password required, e.g.:

```bash
xfreerdp /v:localhost:3389 /size:1024x1024 /cert:ignore
```

(Remmina, Windows `mstsc`, etc. also work against `localhost:3389`.)

## Verifying it works

```bash
# Both pods Running:
kubectl -n k3rdp get pods

# Display geometry / DPI (expect: 1024x1024 pixels, 96x96 dots per inch):
kubectl -n k3rdp exec deploy/x11rdp -- xdpyinfo | grep -E "dimensions|resolution"

# Qt app connected without X errors:
kubectl -n k3rdp logs deploy/qtapp
```

## Swapping in your own Qt application

The sample lives in `images/qtapp/` (`src/main.cpp`, `CMakeLists.txt`). To use
your own app:

1. Replace `src/` and `CMakeLists.txt` (keep the executable target named `qtapp`,
   or adjust `images/qtapp/Dockerfile`'s `COPY --from=build /out/bin/qtapp ...`).
2. Ensure your app uses the X11/xcb platform (already forced via
   `QT_QPA_PLATFORM=xcb`) and honors `DISPLAY`.
3. For the borderless-fullscreen kiosk look, have your top-level window call
   `showFullScreen()` (the sample does). This sets `_NET_WM_STATE_FULLSCREEN`,
   which IceWM honors by dropping all decorations. As a WM-side fallback for apps
   that can't self-fullscreen, add your window's `WM_CLASS` to
   `images/x11rdp/icewm/winoptions` (see that file's header for how to find it).
4. Rebuild and redeploy:
   ```bash
   scripts/build-images.sh
   kubectl -n k3rdp rollout restart deploy/qtapp
   ```

For **Qt 6**, change `images/qtapp/Dockerfile` build deps to `qt6-base-dev`,
runtime deps to the `libqt6*`/`qt6-qpa-plugins` packages, and update
`CMakeLists.txt` to `find_package(Qt6 ...)` / `Qt6::Widgets`.

## Changing resolution or DPI

Display geometry is env-driven on the `x11rdp` Deployment
(`manifests/x11rdp-deployment.yaml`): `SCREEN_GEOMETRY` (`WxHxDepth`) and
`SCREEN_DPI`. Update, then `kubectl apply -k manifests` and restart the pod.
Match the RDP client `/size:` accordingly.

## Layout

| Path | Purpose |
|------|---------|
| `setup.sh` | Install tooling (dnf packages + k3d binary in `/usr/bin`). |
| `scripts/` | `create-cluster`, `build-images`, `deploy`, `connect`, `destroy`. |
| `images/x11rdp/` | Xvfb + icewm + x11vnc + xrdp image and its config. |
| `images/qtapp/` | Sample Qt Widgets app + multi-stage build. |
| `manifests/` | Kustomize: namespace, deployments, RDP + display services. |

## Security note (dev-only)

`Xvfb -ac` disables X access control, and RDP requires no login. This is safe
here because the X11 display is only reachable via a **ClusterIP** Service inside
the cluster, and RDP is bound to `localhost` on your machine. Do **not** expose
this to untrusted networks without adding authentication.

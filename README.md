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
        │  Xvfb :0  (1624x1024x24 fb, -listen tcp, -ac)          │◄── X11 TCP :6000
        │    RandR monitors:  primary 1024x1024 @96  (+600+0)     │      │  (ClusterIP
        │                     secondary 600x400 @120 (+0+624)     │      │   Service
        │  icewm (kiosk WM)                                       │      │   :6000)
        │  x11vnc  ──► :5900  (-nopw, -shared, -forever)          │      │
        │  xrdp    ──► :3389  (libvnc.so module → 127.0.0.1:5900) │      │
        └────────────────────────────────────────────────────────┘      │
                                                                          │
        ┌───────────────────── Pod: qtapp ──────────────────────┐        │
        │  Qt6 Widgets app, QT_QPA_PLATFORM=xcb                  │────────┘
        │  one fullscreen window per monitor                     │
        │  DISPLAY=x11rdp-display.k3rdp.svc.cluster.local:0      │  connects over TCP
        └────────────────────────────────────────────────────────┘
```

**Display:** one X server, **two monitors** in a `1624×1024` framebuffer —
primary `1024×1024 @ 96 DPI` (right), secondary `600×400 @ 120 DPI` (bottom-left,
below the primary). **RDP auth:** none (auto-attaches). **Window mode:** kiosk —
IceWM shows borderless, fullscreen windows with no taskbar or decorations.

## Why this design

A single, persistent display (`:0`) is shared between the Qt app (which connects
over TCP via `DISPLAY`) and the RDP viewer, so both see the *same* screen. xrdp's
native backends spawn a **new** X server per session, which would not be the
display the Qt app draws to. So the pod runs a persistent **Xvfb :0**, exports it
with **x11vnc**, and puts **xrdp** (its `libvnc.so` module) in front to speak RDP.

## Multi-monitor (one X server, two DPIs)

The single Xvfb framebuffer (`1624×1024`) is carved into two **RandR 1.5 virtual
monitors** (`xrandr --setmonitor`, run in `start-x11.sh`). Each declares its own
physical size in mm, so each reports its own DPI (`mm = round(px·25.4 / dpi)`):

| Monitor   | Geometry            | DPI | mm       |
|-----------|---------------------|-----|----------|
| primary   | 1024×1024 at +600+0 | 96  | 271×271  |
| secondary | 600×400  at +0+624  | 120 | 127×85   |

**Qt 6 is required for the app to see both monitors:** its xcb backend reads the
RandR monitor list (including the virtual, output-less secondary) and creates a
`QScreen` per monitor with the right per-monitor DPI. Qt 5 maps a screen to a
RandR *output* only — and Xvfb has a single output — so it would collapse both
into one 96 DPI screen. (A true multi-*output* server, e.g. Xorg + the dummy
driver, would be the alternative; the RandR-monitor + Qt 6 combo avoids it.)

Layout/DPI are env-driven on the `x11rdp` Deployment: `SCREEN_GEOMETRY`,
`SCREEN_DPI`, `PRIMARY_POS`, and `SECONDARY_ENABLE` / `SECONDARY_GEOMETRY` /
`SECONDARY_DPI` / `SECONDARY_POS`. Set `SECONDARY_ENABLE=0` for a single monitor.

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
xfreerdp /v:localhost:3389 /size:1624x1024 /cert:ignore
```

(Remmina, Windows `mstsc`, etc. also work against `localhost:3389`.)

## Verifying it works

```bash
# Both pods Running:
kubectl -n k3rdp get pods

# Two monitors with the right geometry + DPI (mm encodes DPI):
kubectl -n k3rdp exec deploy/x11rdp -- bash -c 'DISPLAY=:0 xrandr --listmonitors'
#   0: primary   1024/271x1024/271+600+0  screen
#   1: secondary  600/127x400/85+0+624

# Qt6 app sees both screens at 96 and 120 DPI:
kubectl -n k3rdp logs deploy/qtapp
#   [qtapp] detected 2 screen(s)
#   [qtapp] screen: primary   ... phys-dpi 96
#   [qtapp] screen: secondary ... phys-dpi 120
```

## Swapping in your own Qt application

The sample lives in `images/qtapp/` (`src/main.cpp`, `CMakeLists.txt`). To use
your own app:

1. Replace `src/` and `CMakeLists.txt` (keep the executable target named `qtapp`,
   or adjust `images/qtapp/Dockerfile`'s `COPY --from=build /out/bin/qtapp ...`).
2. Ensure your app uses the X11/xcb platform (already forced via
   `QT_QPA_PLATFORM=xcb`) and honors `DISPLAY`.
3. For the borderless-fullscreen kiosk look, have your top-level window call
   `showFullScreen()` (the sample does, one window per `QScreen`). This sets
   `_NET_WM_STATE_FULLSCREEN`, which IceWM honors by dropping all decorations. As
   a WM-side fallback for apps that can't self-fullscreen, add your window's
   `WM_CLASS` to `images/x11rdp/icewm/winoptions` (see that file's header).
4. Rebuild and redeploy:
   ```bash
   scripts/build-images.sh
   kubectl -n k3rdp rollout restart deploy/qtapp
   ```

The app is built against **Qt 6** (`images/qtapp/Dockerfile` uses `qt6-base-dev` +
`libqt6*`/`qt6-qpa-plugins`; `CMakeLists.txt` uses `Qt6::Widgets`). Qt 6 is what
lets the app see both RandR monitors as separate `QScreen`s (see *Multi-monitor*
above) — staying on Qt 5 would collapse them into one 96 DPI screen.

## Changing resolution / DPI / monitor layout

All geometry is env-driven on the `x11rdp` Deployment
(`manifests/x11rdp-deployment.yaml`):

| Env | Meaning |
|-----|---------|
| `SCREEN_GEOMETRY` | primary `WxHxDepth` (e.g. `1024x1024x24`) |
| `SCREEN_DPI` | primary DPI + the framebuffer's global DPI |
| `PRIMARY_POS` | primary offset in the framebuffer (`+x+y`) |
| `SECONDARY_ENABLE` | `1` = second monitor, `0` = single monitor |
| `SECONDARY_GEOMETRY` | secondary `WxH` (e.g. `600x400`) |
| `SECONDARY_DPI` | secondary DPI (e.g. `120`) |
| `SECONDARY_POS` | secondary offset in the framebuffer (`+x+y`) |

The Xvfb framebuffer is auto-sized to the bounding box of the enabled monitors
(`images/x11rdp/start-xvfb.sh`). After editing, `kubectl apply -k manifests`,
restart the pod, and match the RDP client `/size:` to the framebuffer.

## Layout

| Path | Purpose |
|------|---------|
| `setup.sh` | Install tooling (dnf packages + k3d binary in `/usr/bin`). |
| `scripts/` | `create-cluster`, `build-images`, `deploy`, `connect`, `destroy`. |
| `images/x11rdp/` | Xvfb (+ RandR monitors) + icewm + x11vnc + xrdp image and config. |
| `images/qtapp/` | Sample Qt6 Widgets app (one window per monitor) + multi-stage build. |
| `manifests/` | Kustomize: namespace, deployments, RDP + display services. |

## Security note (dev-only)

`Xvfb -ac` disables X access control, and RDP requires no login. This is safe
here because the X11 display is only reachable via a **ClusterIP** Service inside
the cluster, and RDP is bound to `localhost` on your machine. Do **not** expose
this to untrusted networks without adding authentication.

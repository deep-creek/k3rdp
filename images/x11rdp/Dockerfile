FROM debian:bookworm-slim

# X11/RDP server pod:
#   Xvfb   -> a persistent, TCP-reachable virtual display :0
#   icewm  -> window manager in kiosk mode: one borderless fullscreen app
#   x11vnc -> exports display :0 over VNC on :5900
#   xrdp   -> speaks RDP on :3389, bridging to x11vnc via its libvnc.so module
#
# supervisord keeps the group of processes alive; start-x11.sh sequences them.

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
        xvfb \
        x11vnc \
        icewm \
        xrdp \
        x11-utils \
        x11-xserver-utils \
        xauth \
        dbus-x11 \
        supervisor \
        procps \
        ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Our xrdp config: listen on 3389 and auto-attach to the running x11vnc.
COPY xrdp.ini /etc/xrdp/xrdp.ini
COPY supervisord.conf /etc/supervisor/supervisord.conf
COPY start-x11.sh /usr/local/bin/start-x11.sh
# IceWM kiosk config: no taskbar, single borderless fullscreen app.
# Debian's IceWM reads system config from /etc/X11/icewm (its CFGDIR).
COPY icewm/ /etc/X11/icewm/
RUN chmod +x /usr/local/bin/start-x11.sh

# Display geometry / DPI (overridable at runtime via env in the Deployment).
ENV DISPLAY_NUM=0 \
    SCREEN_GEOMETRY=1024x1024x24 \
    SCREEN_DPI=96 \
    VNC_PORT=5900

# 3389 = RDP (external), 5900 = VNC (external), 6000 = X11 :0 (cluster-internal).
EXPOSE 3389 5900 6000

CMD ["/usr/bin/supervisord", "-c", "/etc/supervisor/supervisord.conf"]

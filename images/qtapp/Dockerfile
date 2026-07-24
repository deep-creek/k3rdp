# ---- build stage: compile the Qt Widgets app ----
FROM debian:bookworm-slim AS build

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential \
        cmake \
        qt6-base-dev \
        libx11-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /src
COPY CMakeLists.txt ./
COPY src ./src
RUN cmake -S . -B build -DCMAKE_BUILD_TYPE=Release \
    && cmake --build build --parallel \
    && cmake --install build --prefix /out

# ---- runtime stage: Qt5 + xcb platform plugin only ----
FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
        libqt6widgets6 \
        libqt6gui6 \
        libqt6core6 \
        qt6-qpa-plugins \
        libx11-6 \
        libxcb-cursor0 \
        libxcb-xinerama0 \
        libxcb-icccm4 \
        libxcb-image0 \
        libxcb-keysyms1 \
        libxcb-randr0 \
        libxcb-render-util0 \
        libxcb-shape0 \
        libxcb-xkb1 \
        libxkbcommon-x11-0 \
    && rm -rf /var/lib/apt/lists/*

COPY --from=build /out/bin/qtapp /usr/local/bin/qtapp
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# Use the X11 (xcb) platform plugin and force 96 DPI to match the display.
ENV QT_QPA_PLATFORM=xcb \
    QT_FONT_DPI=96

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["qtapp"]

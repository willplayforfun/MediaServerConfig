# Moonlight endering straight to DRM/KMS. 
# It picks eglfs/KMSDRM when there's no X11/Wayland.

FROM debian:trixie-slim AS build

# Built from source. Bump ML_VERSION to update (github.com/moonlight-stream/moonlight-qt/releases).
ARG ML_VERSION=6.2.0
RUN rm -f /etc/apt/apt.conf.d/docker-clean
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends \
        build-essential \
        ca-certificates \
        curl \
        pkg-config \
        qmake6 \
        qt6-base-dev \
        qt6-declarative-dev \
        libqt6svg6-dev \
        libegl-dev \
        libgl-dev \
        libgles-dev \
        libopus-dev \
        libsdl2-dev \
        libsdl2-ttf-dev \
        libssl-dev \
        libavcodec-dev \
        libavformat-dev \
        libswscale-dev \
        libva-dev \
        libvdpau-dev \
        libdrm-dev
RUN curl -fsSL --retry 5 --retry-all-errors -o /src.tar.gz \
        "https://github.com/moonlight-stream/moonlight-qt/releases/download/v${ML_VERSION}/MoonlightSrc-${ML_VERSION}.tar.gz"


#  - "embedded" is upstream's build for single-purpose devices.
RUN mkdir /usr/src/moonlight && tar -xzf /src.tar.gz -C /usr/src/moonlight \
    && cd /usr/src/moonlight \
    && qmake6 PREFIX=/usr CONFIG+=release CONFIG+=embedded \
        CONFIG+=disable-x11 CONFIG+=disable-wayland moonlight-qt.pro \
    && make -j"$(nproc)" \
    && make install INSTALL_ROOT=/out

FROM debian:trixie-slim

# Keeps downloaded .debs between builds (Debian's docker-clean hook would delete them).
RUN rm -f /etc/apt/apt.conf.d/docker-clean

#  - The VA packages give hardware decode.
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends \
        libqt6quick6 \
        libqt6quickcontrols2-6 \
        libqt6svg6 \
        libqt6network6 \
        libqt6opengl6 \
        qml6-module-qtquick \
        qml6-module-qtquick-controls \
        qml6-module-qtquick-layouts \
        qml6-module-qtquick-templates \
        qml6-module-qtquick-window \
        qml6-module-qtqml-workerscript \
        qt6-qpa-plugins \
        qt6-svg-plugins \
        libsdl2-2.0-0 \
        libsdl2-ttf-2.0-0 \
        libopus0 \
        libavcodec61 \
        libavformat61 \
        libswscale8 \
        libva2 \
        libva-drm2 \
        libvdpau1 \
        libproxy1v5 \
        libpulse0 \
        libdrm2 \
        libegl1 \
        libgles2 \
        libgl1-mesa-dri \
        libgbm1 \
        libinput10 \
        intel-media-va-driver \
        mesa-va-drivers \
        libasound2-plugins \
        fonts-dejavu-core \
        ca-certificates

COPY --from=build /out/usr/bin/moonlight /usr/bin/moonlight

# entrypoint.sh is bind-mounted by tv/compose.yml so editing doesn't require a rebuild.
ENTRYPOINT ["/bin/sh", "/entrypoint.sh"]

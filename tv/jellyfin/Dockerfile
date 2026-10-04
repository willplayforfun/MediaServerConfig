# Jellyfin Desktop (Qt WebEngine + libmpv) rendering straight to DRM/KMS via
# Qt's eglfs platform. Upstream's .deb is installed so apt pulls in its Qt deps.
#  - Bump JF_VERSION to update (releases: github.com/jellyfin/jellyfin-desktop).
#  - The VA packages give mpv hardware decode.
FROM debian:bookworm-slim

ARG JF_VERSION=1.12.0

RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
    && curl -fsSL -o /tmp/jmp.deb \
        "https://github.com/jellyfin/jellyfin-desktop/releases/download/v${JF_VERSION}/jellyfin-media-player_${JF_VERSION}-bookworm.deb" \
    && apt-get install -y --no-install-recommends \
        /tmp/jmp.deb \
        libegl1 \
        libgles2 \
        libgl1-mesa-dri \
        libgbm1 \
        libinput10 \
        libva-drm2 \
        intel-media-va-driver \
        mesa-va-drivers \
        libasound2-plugins \
        fonts-dejavu-core \
    && apt-get purge -y curl \
    && apt-get autoremove -y \
    && rm -rf /tmp/jmp.deb /var/lib/apt/lists/*

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]

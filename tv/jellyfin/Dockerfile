# Jellyfin Desktop (Qt WebEngine + libmpv) rendering straight to DRM/KMS via
# Qt's eglfs platform. Upstream's .deb is installed so apt pulls in its Qt deps.
#  - Bump JF_VERSION to update (releases: github.com/jellyfin/jellyfin-desktop).
#  - The VA packages give mpv hardware decode.
#  - entrypoint.sh is bind-mounted by tv/compose.yml, so editing it needs a
#    restart, not a rebuild.

# The download is its own stage so changing the package list doesn't redo it.
FROM debian:bookworm-slim AS fetch
ARG JF_VERSION=1.12.0
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    rm -f /etc/apt/apt.conf.d/docker-clean \
    && apt-get update && apt-get install -y --no-install-recommends ca-certificates curl \
    && curl -fsSL -o /jmp.deb \
        "https://github.com/jellyfin/jellyfin-desktop/releases/download/v${JF_VERSION}/jellyfin-media-player_${JF_VERSION}-bookworm.deb"

FROM debian:bookworm-slim

# Keeps downloaded .debs between builds (Debian's docker-clean hook would delete them).
RUN rm -f /etc/apt/apt.conf.d/docker-clean
RUN --mount=type=bind,from=fetch,source=/jmp.deb,target=/tmp/jmp.deb \
    --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends \
        /tmp/jmp.deb \
        ca-certificates \
        libegl1 \
        libgles2 \
        libgl1-mesa-dri \
        libgbm1 \
        libinput10 \
        libva-drm2 \
        intel-media-va-driver \
        mesa-va-drivers \
        libasound2-plugins \
        fonts-dejavu-core

ENTRYPOINT ["/bin/sh", "/entrypoint.sh"]

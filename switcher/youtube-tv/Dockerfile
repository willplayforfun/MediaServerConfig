# cog (WPE's minimal kiosk browser launcher) renders straight to DRM/KMS the
# same way kodi-gbm does - no X11/Wayland session needed, so it can take
# over the display the instant the switcher stops the kodi container.
#
# Package names below are Debian bookworm's as of this writing and are
# UNVERIFIED - if `apt-get install cog` fails, or pulls in an unexpectedly
# old WPE WebKit, check `apt-cache search cog wpewebkit` on the actual build
# host and adjust. Same kind of empirical iteration the keyring fix in
# ../../kodi/Dockerfile needed.
FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
        cog \
        python3 \
        python3-evdev \
        ca-certificates \
    && rm -rf /var/lib/apt/lists/*

COPY entrypoint.sh /entrypoint.sh
COPY watcher.py /watcher.py
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]

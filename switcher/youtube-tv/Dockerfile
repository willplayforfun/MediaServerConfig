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

# libgles2/libegl1/libgl1-mesa-dri: the `cog` package doesn't pull these in
# as hard dependencies, but WPE's renderer process dlopen()s libGLESv2 at
# runtime for its EGL/GBM compositing - without them it loads the page,
# then immediately crashes ("Couldn't open libGLESv2.so.2") and reload-loops.
# libgl1-mesa-dri is the actual Intel iGPU driver behind EGL/GLES, not just
# the loader libs, so hardware acceleration needs it too.
RUN apt-get update && apt-get install -y --no-install-recommends \
        cog \
        libegl1 \
        libgles2 \
        libgl1-mesa-dri \
        python3 \
        python3-evdev \
        ca-certificates \
    && rm -rf /var/lib/apt/lists/*

COPY entrypoint.sh /entrypoint.sh
COPY watcher.py /watcher.py
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]

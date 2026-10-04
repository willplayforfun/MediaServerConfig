# Kiosk browser for TV apps: cog (WPE WebKit's minimal launcher) rendering
# straight to DRM/KMS - no X11/Wayland session - so it can take over the
# display the moment the hub stops whatever was on screen. One image serves
# every browser-based app (the launcher, YouTube, ...); the URL and user
# agent come from the environment.
#
# Package names are Debian bookworm's.
#  - libegl1/libgles2/libgl1-mesa-dri: cog doesn't depend on them, but WPE's
#    renderer dlopen()s libGLESv2 at runtime, and libgl1-mesa-dri is the
#    actual GPU driver (Intel/AMD) behind EGL/GLES. Without them the page loads,
#    then crashes ("Couldn't open libGLESv2.so.2") in a reload loop.
#  - gstreamer1.0-*: WPE plays all media through GStreamer. alsa is the
#    audio sink, libav/plugins-good/-bad the software decoders (VP9, H.264,
#    Opus, AAC for YouTube), vaapi plus a VA-API driver hardware decode
#    (intel-media-va-driver for Intel, mesa-va-drivers for AMD).
FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
        cog \
        libegl1 \
        libgles2 \
        libgl1-mesa-dri \
        gstreamer1.0-alsa \
        gstreamer1.0-plugins-base \
        gstreamer1.0-plugins-good \
        gstreamer1.0-plugins-bad \
        gstreamer1.0-libav \
        gstreamer1.0-vaapi \
        intel-media-va-driver \
        mesa-va-drivers \
        fonts-dejavu-core \
        ca-certificates \
    && rm -rf /var/lib/apt/lists/*

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]

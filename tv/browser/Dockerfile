# Kiosk browser shared by every browser-based TV app: cog (WPE WebKit)
# rendering straight to DRM/KMS. URL and user agent come from the env.
#  - libegl1/libgles2/libgl1-mesa-dri aren't cog dependencies, but WPE
#    dlopen()s GLES at runtime; without them the page crash-loops.
#  - WPE plays all media through GStreamer; vaapi plus the VA drivers give
#    hardware decode.
FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
        cog \
        libegl1 \
        libgles2 \
        libgl1-mesa-dri \
        gstreamer1.0-alsa \
        gstreamer1.0-gl \
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

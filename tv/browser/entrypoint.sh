#!/bin/sh
# Points ALSA's default device at the HDMI output, then execs cog on
# COG_URL. The container runs with init: true (tini as PID 1), so
# `docker stop` from the hub tears it down cleanly.
#
# Env:
#   COG_URL         page to show (required)
#   COG_USER_AGENT  optional user agent override (YouTube's TV app only
#                   loads for TV user agents)
#   AUDIO_DEVICE    ALSA device for sound (default hdmi:CARD=PCH,DEV=0)
set -e

: "${COG_URL:?COG_URL must be set}"

# `plug` converts whatever rate/format GStreamer hands it into something the
# HDMI device accepts.
cat > /etc/asound.conf <<EOF
pcm.!default {
    type plug
    slave.pcm "${AUDIO_DEVICE:-hdmi:CARD=PCH,DEV=0}"
}
EOF

# Cookies (logins) and site data persist under XDG_DATA_HOME, which
# compose points at a per-app volume.
set -- --platform=drm --cookie-jar=sqlite --bg-color=black
if [ -n "${COG_USER_AGENT:-}" ]; then
    set -- "$@" "--user-agent=${COG_USER_AGENT}"
fi

exec cog "$@" "${COG_URL}"

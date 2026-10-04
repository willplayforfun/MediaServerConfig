#!/bin/sh
# Points ALSA's default device at HDMI, then runs cog on COG_URL.
# Env: COG_URL (required), COG_USER_AGENT, AUDIO_DEVICE.
set -e

: "${COG_URL:?COG_URL must be set}"

# `plug` converts to a rate/format the HDMI device accepts.
cat > /etc/asound.conf <<EOF
pcm.!default {
    type plug
    slave.pcm "${AUDIO_DEVICE:-hdmi:CARD=PCH,DEV=0}"
}
EOF

# Logins persist under XDG_DATA_HOME (a per-app volume).
set -- --platform=drm --cookie-jar=sqlite --bg-color=black
if [ -n "${COG_USER_AGENT:-}" ]; then
    set -- "$@" "--user-agent=${COG_USER_AGENT}"
fi

exec cog "$@" "${COG_URL}"

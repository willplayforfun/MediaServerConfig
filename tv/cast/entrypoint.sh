#!/bin/sh
# Runs Moonlight with the settings in /config/cast.conf, re-read on every launch.
set -e

: "${APP:?APP must be set}"
. "/config/${APP}.conf"

ln -sf /config/asound.conf /etc/asound.conf

export XDG_RUNTIME_DIR=/tmp/runtime
mkdir -p "${XDG_RUNTIME_DIR}"
chmod 700 "${XDG_RUNTIME_DIR}"

# Skips the menu. When the stream ends, the hub returns to the launcher.
if [ -n "${CAST_HOST:-}" ]; then
    exec moonlight stream "${CAST_HOST}" "${CAST_APP:-Desktop}"
fi
exec moonlight

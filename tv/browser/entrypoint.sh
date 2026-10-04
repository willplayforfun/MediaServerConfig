#!/bin/sh
# Runs cog with the settings in /config/$APP.conf, re-read on every launch.
set -e

: "${APP:?APP must be set}"
. "/config/${APP}.conf"
: "${COG_URL:?COG_URL must be set in /config/${APP}.conf}"

ln -sf /config/asound.conf /etc/asound.conf

# Logins persist under XDG_DATA_HOME (a per-app volume).
set -- --platform=drm --cookie-jar=sqlite --bg-color=black
if [ -n "${COG_USER_AGENT:-}" ]; then
    set -- "$@" "--user-agent=${COG_USER_AGENT}"
fi

exec cog "$@" "${COG_URL}"

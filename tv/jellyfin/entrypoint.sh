#!/bin/sh
# Runs Jellyfin Desktop on Qt's eglfs (DRM/KMS) with the settings in
# /config/jellyfin.conf, re-read on every launch.
set -e

: "${APP:?APP must be set}"
. "/config/${APP}.conf"

ln -sf /config/asound.conf /etc/asound.conf

export QT_QPA_PLATFORM=eglfs
export QT_QPA_EGLFS_INTEGRATION=eglfs_kms
export QT_QPA_EGLFS_KMS_ATOMIC=1
export QT_QPA_EGLFS_ALWAYS_SET_MODE=1
# Chromium refuses to run as root with its sandbox on.
export QTWEBENGINE_DISABLE_SANDBOX=1
export XDG_RUNTIME_DIR=/tmp/runtime
mkdir -p "${XDG_RUNTIME_DIR}"
chmod 700 "${XDG_RUNTIME_DIR}"

# JF_ARGS is deliberately unquoted so it splits into separate flags.
# shellcheck disable=SC2086
exec jellyfinmediaplayer ${JF_ARGS:-}

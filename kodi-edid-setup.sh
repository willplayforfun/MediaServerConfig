#!/bin/bash
# kodi-edid-setup.sh
# Applies captured EDID overrides (kodi/edid-overrides/*.bin) directly to the
# host's DRM debugfs, for displays/transmitters that advertise broken or
# incomplete EDID (most commonly: missing the HDMI audio capability block)
# even though the real display supports audio fine and video works.
#
# Debugfs state does NOT persist across reboots, so this must be re-run
# after every boot, before Kodi first reads the connector - either by hand,
# or wired into a cron @reboot job / systemd oneshot unit.
#
# Usage:
#   sudo bash kodi-edid-setup.sh
#
# Safe to re-run.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EDID_DIR="${SCRIPT_DIR}/kodi/edid-overrides"
DEBUGFS_DRI="/sys/kernel/debug/dri"

if [ "$(id -u)" -ne 0 ]; then
    echo "[kodi-edid-setup] Must be run as root (debugfs write access). Try: sudo bash $0" >&2
    exit 1
fi

if [ ! -d "$DEBUGFS_DRI" ]; then
    echo "[kodi-edid-setup] $DEBUGFS_DRI not found." >&2
    echo "[kodi-edid-setup] Is debugfs mounted? Try: mount -t debugfs none /sys/kernel/debug" >&2
    exit 1
fi

shopt -s nullglob
files=("$EDID_DIR"/*.bin)
shopt -u nullglob

if [ ${#files[@]} -eq 0 ]; then
    echo "[kodi-edid-setup] No .bin files in $EDID_DIR. Nothing to do."
    exit 0
fi

for f in "${files[@]}"; do
    name="$(basename "$f" .bin)"
    applied=0

    for card_dir in "$DEBUGFS_DRI"/*/; do
        connector_dir="${card_dir}${name}"
        override="${connector_dir}/edid_override"
        force="${connector_dir}/force"

        if [ -e "$override" ]; then
            echo "[kodi-edid-setup] Applying $f -> $override"
            cat "$f" > "$override"

            # edid_override only takes effect on the next detect cycle, so
            # force one now instead of waiting for a real hotplug event.
            echo off > "$force" 2>/dev/null || true
            echo on  > "$force" 2>/dev/null || true

            applied=1
            break
        fi
    done

    if [ "$applied" -eq 0 ]; then
        echo "[kodi-edid-setup] WARNING: no connector named '$name' found under $DEBUGFS_DRI. Check the filename matches a real connector (see /sys/class/drm/)." >&2
    fi
done

echo "[kodi-edid-setup] Done."

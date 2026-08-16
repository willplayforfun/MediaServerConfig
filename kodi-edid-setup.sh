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
# Files are named descriptively (e.g. aurora-pro.bin), not after a connector
# - connector names can change across reboots/re-cabling, and aren't stable
# enough to bake into a filename. Instead, this scans the real connectors on
# every run and asks interactively which (if any) each file should go to.
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

# Scan real connectors (sysfs, not debugfs - sysfs has the human-readable
# status). Strip the "cardN-" prefix so names match the debugfs layout used
# below (/sys/kernel/debug/dri/<N>/<connector>/), e.g. card0-HDMI-A-1 -> HDMI-A-1.
conn_names=()
conn_status=()
for d in /sys/class/drm/card*-*/; do
    [ -f "${d}status" ] || continue
    base="$(basename "$d")"
    conn_names+=("$(echo "$base" | sed -E 's/^card[0-9]+-//')")
    conn_status+=("$(cat "${d}status" 2>/dev/null || echo unknown)")
done

if [ ${#conn_names[@]} -eq 0 ]; then
    echo "[kodi-edid-setup] No DRM connectors found under /sys/class/drm/. Nothing to apply overrides to." >&2
    exit 1
fi

echo "[kodi-edid-setup] Found connectors:"
for i in "${!conn_names[@]}"; do
    printf "  %d) %s (%s)\n" "$((i + 1))" "${conn_names[$i]}" "${conn_status[$i]}"
done

for f in "${files[@]}"; do
    echo
    echo "[kodi-edid-setup] File: $(basename "$f")"
    read -r -p "  Apply to which connector above? [blank to skip] " choice

    if [ -z "$choice" ]; then
        echo "  Skipped."
        continue
    fi

    if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt "${#conn_names[@]}" ]; then
        echo "  '$choice' isn't one of the listed numbers, skipping $(basename "$f")." >&2
        continue
    fi

    name="${conn_names[$((choice - 1))]}"
    applied=0

    for card_dir in "$DEBUGFS_DRI"/*/; do
        connector_dir="${card_dir}${name}"
        override="${connector_dir}/edid_override"
        force="${connector_dir}/force"

        if [ -e "$override" ]; then
            echo "  Applying $(basename "$f") -> $override"
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
        echo "  WARNING: '$name' has no matching entry under $DEBUGFS_DRI (debugfs and sysfs connector names normally match - if they don't here, something's unusual)." >&2
    fi
done

echo
echo "[kodi-edid-setup] Done."

#!/bin/bash
# hdmi-audio-reprobe.sh
# Re-probes the HDA controller that carries the Intel HDMI audio codec, so
# HDMI ports the codec missed at boot get registered. Installed as a boot
# service by install-hdmi-audio-fix.sh - see that script for background.
#
# Not intended to be run manually.

set -u

# Wait (up to 30s) for i915 to register an HDMI connector, so display init
# has got far enough that the codec will expose all of its pins.
for _ in $(seq 1 30); do
    ls /sys/class/drm/card*-HDMI-A-*/status >/dev/null 2>&1 && break
    sleep 1
done
sleep 2

# Find the PCI device of the sound card whose codec list includes Intel HDMI.
dev=""
for card in /proc/asound/card[0-9]*; do
    if grep -qs "HDMI" "$card"/codec#*; then
        dev="$(readlink -f "/sys/class/sound/$(basename "$card")/device")"
        break
    fi
done

if [ -z "$dev" ] || [ ! -e "$dev/remove" ]; then
    echo "hdmi-audio-reprobe: no Intel HDMI audio controller found, nothing to do"
    exit 0
fi

echo "hdmi-audio-reprobe: re-probing $(basename "$dev")"
echo 1 > "$dev/remove"
sleep 1
echo 1 > /sys/bus/pci/rescan
sleep 3
grep -hE 'monitor_name' /proc/asound/card*/eld#* 2>/dev/null | sed 's/^/hdmi-audio-reprobe: /' || true

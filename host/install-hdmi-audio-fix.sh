#!/bin/bash
# install-hdmi-audio-fix.sh
# Fixes silent HDMI audio on Intel graphics.
#
# Symptom: HDMI video works but there's no sound. Every
# /proc/asound/card*/eld#* shows eld_valid 0, and dmesg shows
# "HDMI: pin NID 0x... not registered".
# Cause: at boot the audio driver sets up before the display is ready, misses
# the HDMI port, and never picks it up later.
#
# Offers one of two fixes (choosing one removes the other):
#   1) Recommended: a boot service that resets the audio device once the
#      display is up (hdmi-audio-reprobe.sh), before Docker starts.
#   2) Load the graphics driver (i915) before the audio driver. Lighter, but
#      didn't help on this server.
#
# Must be run as root on the OMV host.
#
# Usage:
#   sudo /opt/docker/host/install-hdmi-audio-fix.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPROBE_SRC="${SCRIPT_DIR}/hdmi-audio-reprobe.sh"
HELPER=/usr/local/sbin/hdmi-audio-reprobe
UNIT_NAME=hdmi-audio-reprobe.service
UNIT=/etc/systemd/system/$UNIT_NAME
SOFTDEP=/etc/modprobe.d/hdmi-audio-after-i915.conf

if [ "$(id -u)" -ne 0 ]; then
    echo "Error: must be run as root (try: sudo $0)" >&2
    exit 1
fi

remove_reprobe() {
    if [ -e "$UNIT" ] || [ -e "$HELPER" ]; then
        systemctl disable "$UNIT_NAME" 2>/dev/null || true
        rm -f "$UNIT" "$HELPER"
        systemctl daemon-reload
        echo "Removed boot re-probe service."
    fi
}

remove_softdep() {
    if [ -e "$SOFTDEP" ]; then
        rm -f "$SOFTDEP"
        echo "Removed $SOFTDEP"
        update-initramfs -u
    fi
}

install_reprobe() {
    install -m 755 "$REPROBE_SRC" "$HELPER"
    echo "Installed $REPROBE_SRC -> $HELPER"

    cat > "$UNIT" <<EOF
[Unit]
Description=Re-probe HDMI audio after display init (fixes unregistered HDMI pin)
After=systemd-modules-load.service systemd-udev-trigger.service
Before=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=$HELPER

[Install]
WantedBy=multi-user.target
EOF
    echo "Wrote $UNIT"

    systemctl daemon-reload
    systemctl enable "$UNIT_NAME"

    echo
    echo "Running the re-probe once now..."
    "$HELPER"

    echo
    echo "Done - applied now and on every boot."
    echo "Boot log: journalctl -b -u $UNIT_NAME"
}

install_softdep() {
    echo "softdep snd_hda_intel pre: i915" > "$SOFTDEP"
    echo "Wrote $SOFTDEP"
    # Either module can end up in the initramfs depending on its config, and
    # the softdep has to be visible wherever they load.
    update-initramfs -u
    echo
    echo "Done - takes effect after a reboot."
}

echo "HDMI audio fix - choose one:"
echo "  1) Boot re-probe service (recommended)"
echo "  2) Module load order (lighter change)"
echo "  3) Remove both"
read -r -p "Choice [1]: " choice

case "${choice:-1}" in
    1) remove_softdep; install_reprobe ;;
    2) remove_reprobe; install_softdep ;;
    3) remove_reprobe; remove_softdep; echo "Both fixes removed."; exit 0 ;;
    *) echo "Unknown choice '$choice'." >&2; exit 1 ;;
esac

echo
echo "Check that the connected HDMI port is registered:"
echo "  grep -E 'eld_valid|monitor_name' /proc/asound/card*/eld#*"
echo "One entry should read eld_valid 1 with your display's name."

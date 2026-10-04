#!/bin/bash
# install-hdmi-audio-fix.sh
# Fixes silent HDMI audio on Intel iGPUs caused by a boot-time driver race.
#
# Symptom: HDMI video works, the display's EDID advertises audio, but every
# /proc/asound/card*/eld#* reads eld_valid 0, speaker-test on the hdmi:
# devices is silent, and dmesg shows "HDMI: pin NID 0x... not registered".
#
# Cause: the HDA controller probes the HDMI audio codec before the display
# side is fully up, and at that moment the codec only exposes some of its
# pins - so the connected port's pin is never registered, and every later
# "display connected" notification from i915 is dropped.
#
# Two fixes are offered (picking one removes the other):
#
#   1) Boot re-probe service (recommended). A systemd oneshot that, once the
#      DRM HDMI connector exists, runs scripts/hdmi-audio-reprobe.sh: it
#      removes and rescans the HDA controller's PCI device so it re-probes
#      with every pin visible. Runs before docker.service, so nothing is
#      holding the audio device yet. Works even where fixing the load order
#      alone does not.
#
#   2) Module load order. A modprobe softdep so i915 always loads before
#      snd_hda_intel. Lighter touch, and enough on some hardware - but on
#      others the race is about how far display init has got rather than
#      module load order, and only the re-probe helps.
#
# Must be run as root on the OMV host.
#
# Usage:
#   sudo /opt/docker/install-hdmi-audio-fix.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPROBE_SRC="${SCRIPT_DIR}/scripts/hdmi-audio-reprobe.sh"
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

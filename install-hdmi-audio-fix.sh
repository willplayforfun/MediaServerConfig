#!/bin/bash
# install-hdmi-audio-fix.sh
# Fixes silent HDMI audio on Intel iGPUs caused by a boot-time driver race.
#
# Symptom: HDMI video works, the display's EDID advertises audio, but every
# /proc/asound/card*/eld#* reads eld_valid 0, speaker-test on the hdmi:
# devices is silent, and dmesg shows "HDMI: pin NID 0x7 not registered".
#
# Cause: the HDA controller probes the HDMI audio codec before the display
# side is fully up, and at that moment the codec only exposes some of its
# pins - so the connected port's pin is never registered, and every later
# "display connected" notification from i915 is dropped.
#
# Two fixes are offered (picking one removes the other):
#
#   1) Boot re-probe service (recommended). A systemd oneshot that, once the
#      DRM HDMI connector exists, removes and rescans the HDA controller's
#      PCI device so it re-probes with every pin visible. Runs before
#      docker.service, so nothing is holding the audio device yet. Confirmed
#      working on a Skylake iGPU with the 7.0 backports kernel.
#
#   2) Module load order. A modprobe softdep so i915 always loads before
#      snd_hda_intel. Lighter touch, and enough on some hardware - but it did
#      NOT fix the Skylake/7.0 case above, where the race is about how far
#      display init has got rather than module load order.
#
# Must be run as root on the OMV host.
#
# Usage:
#   sudo /opt/docker/install-hdmi-audio-fix.sh

set -euo pipefail

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
    cat > "$HELPER" <<'EOF'
#!/bin/bash
# Re-probes the HDA controller that carries the Intel HDMI audio codec.
# Installed by install-hdmi-audio-fix.sh - see that script for background.
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
EOF
    chmod +x "$HELPER"
    echo "Wrote $HELPER"

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
echo "  1) Boot re-probe service (recommended; confirmed on Skylake + 7.0 kernel)"
echo "  2) Module load order (lighter; didn't help on Skylake + 7.0 kernel)"
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

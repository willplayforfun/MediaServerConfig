#!/bin/bash
# install-hdmi-audio-fix.sh
# Fixes silent HDMI audio on Intel iGPUs caused by a boot-time driver race.
#
# Symptom: HDMI video works, the display's EDID advertises audio, but every
# /proc/asound/card*/eld#* reads eld_valid 0, speaker-test on the hdmi:
# devices is silent, and dmesg shows "HDMI: pin NID 0x7 not registered".
#
# Cause: snd_hda_intel probes the HDMI audio codec before i915 has finished
# initialising the display side. At that moment the codec only exposes some
# of its pins, so the connected port's pin is never registered, and every
# later "display connected" notification from i915 is dropped. (Seen on a
# Skylake iGPU with the 7.0 backports kernel; a PCI remove/rescan of the
# audio controller after boot makes it work, which is how this was confirmed.)
#
# Fix: a modprobe softdep so i915 always loads before snd_hda_intel.
# Must be run as root on the OMV host, then reboot.
#
# Usage:
#   sudo /opt/docker/install-hdmi-audio-fix.sh

set -euo pipefail

CONF=/etc/modprobe.d/hdmi-audio-after-i915.conf

if [ "$(id -u)" -ne 0 ]; then
    echo "Error: must be run as root (try: sudo $0)" >&2
    exit 1
fi

echo "softdep snd_hda_intel pre: i915" > "$CONF"
echo "Wrote $CONF"

# Either module can end up in the initramfs depending on its config, and the
# softdep has to be visible wherever they load.
echo "Updating initramfs..."
update-initramfs -u

echo
echo "Done. Reboot, then check that the connected HDMI port is registered:"
echo "  grep -E 'eld_valid|monitor_name' /proc/asound/card*/eld#*"
echo "One entry should read eld_valid 1 with your display's name."

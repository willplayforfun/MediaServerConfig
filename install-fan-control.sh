#!/bin/bash
# install-fan-control.sh
# Sets up quiet fan speed control via lm-sensors + fancontrol.
# Installs packages, detects hardware, then runs the interactive pwmconfig
# wizard so you can tune a thermal curve for your specific motherboard.
# Must be run as root on the OMV host.
#
# Usage:
#   sudo /opt/docker/install-fan-control.sh

set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
    echo "Error: must be run as root (try: sudo $0)" >&2
    exit 1
fi

echo "Installing lm-sensors and fancontrol..."
apt-get install -y lm-sensors fancontrol

echo
echo "Detecting hardware sensors (this may take a minute)..."
# --auto answers yes to all probes; writes discovered modules to /etc/modules
# so they load on every boot.
sensors-detect --auto

echo
echo "Starting fan curve configuration."
echo "pwmconfig will probe your hardware and walk you through setting speed curves."
echo "Suggested values for a quiet NAS:"
echo "  MINTEMP ~40C  — fans at minimum below this temperature"
echo "  MAXTEMP ~70C  — fans at maximum above this temperature"
echo "  MINPWM  ~80   — lowest PWM the fan will spin reliably (~30%)"
echo "  MAXPWM  ~255  — full speed ceiling"
echo
pwmconfig

echo
systemctl enable --now fancontrol

echo
echo "Done. fancontrol is running."
echo "  Check status:     systemctl status fancontrol"
echo "  Current readings: sensors"
echo "  Adjust the curve: nano /etc/fancontrol && systemctl restart fancontrol"

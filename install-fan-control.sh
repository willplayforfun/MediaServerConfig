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

# sensors-detect doesn't always find Nuvoton/Winbond fan controller chips
# (common on Intel consumer boards) because they sit at non-standard addresses.
# Try the two most common drivers and load them into /etc/modules if they
# expose PWM controls.
echo
echo "Probing for additional fan controller modules..."
_found_pwm=false
for _mod in nct6775 it87; do
    if modprobe "$_mod" 2>/dev/null; then
        if find /sys/class/hwmon -name 'pwm[0-9]' 2>/dev/null | grep -q .; then
            echo "  Found PWM controls via module '$_mod'."
            if ! grep -qx "$_mod" /etc/modules 2>/dev/null; then
                echo "$_mod" >> /etc/modules
            fi
            _found_pwm=true
            break
        else
            modprobe -r "$_mod" 2>/dev/null || true
        fi
    fi
done

if ! $_found_pwm; then
    echo
    echo "WARNING: No PWM fan controls found after probing all known drivers."
    echo "Your motherboard may not expose fan control to the OS."
    echo "Consider setting fan curves in BIOS instead."
    echo
    echo "If you believe fan control should be available, check:"
    echo "  dmesg | grep -i hwmon"
    echo "  find /sys/class/hwmon -name 'pwm*'"
    exit 1
fi

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

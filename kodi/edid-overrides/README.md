# Kodi EDID overrides

Drop captured raw EDID binaries here to fix displays/transmitters that
advertise broken or incomplete EDID (most commonly: missing HDMI audio
capability). [kodi-edid-setup.sh](../../kodi-edid-setup.sh) applies every
file here to the host's DRM debugfs.

Run it as root after every boot, before starting Kodi - debugfs overrides
don't survive a reboot, so this isn't a one-time setup step:

```bash
sudo bash kodi-edid-setup.sh
```

(wire it into a cron `@reboot` job or a systemd oneshot unit if you want it
applied automatically instead of by hand each time).

Name each file after the DRM connector it should override, e.g.:

```
HDMI-A-1.bin
```

Find the real connector name on the server with:

```bash
ls /sys/class/drm/ | grep -E 'HDMI|DP'
```

(check `cat /sys/class/drm/<name>/status` for `connected` to confirm which
one is actually in use).

To capture a real EDID from a display, connect it directly to a machine
(bypassing any transmitter/extender) and read it from `/sys/class/drm/<connector>/edid`
on Linux, or on Windows, read it out of the registry:

```powershell
$edid = (Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Enum\DISPLAY\<hwid>\<instance>\Device Parameters" -Name EDID).EDID
[System.IO.File]::WriteAllBytes("edid-name.bin", $edid)
```

These files are machine-specific (tied to your actual display's hardware
ID), so they're gitignored — this README is here just to keep the directory
present in checkouts.

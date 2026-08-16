# Kodi EDID overrides

Drop captured raw EDID binaries here to fix displays/transmitters that
advertise broken or incomplete EDID (most commonly: missing HDMI audio
capability). Name them descriptively (e.g. `aurora-pro.bin`) - filenames
don't need to match a connector name.

Run [kodi-edid-setup.sh](../../kodi-edid-setup.sh) as root after every
boot, before starting Kodi - debugfs overrides don't survive a reboot, so
this isn't a one-time setup step:

```bash
sudo bash kodi-edid-setup.sh
```

It scans the real DRM connectors on every run (connector names/ordering can
shift across reboots or re-cabling) and asks, per file, which connector (if
any) to apply it to - so it's interactive by design and isn't a fit for an
unattended cron `@reboot` job as-is.

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

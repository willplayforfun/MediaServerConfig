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

## Capturing a source EDID

To capture a real EDID from a display, connect it directly to a machine
(bypassing any transmitter/extender) and read it from `/sys/class/drm/<connector>/edid`
on Linux, or on Windows, read it out of the registry:

```powershell
$edid = (Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Enum\DISPLAY\<hwid>\<instance>\Device Parameters" -Name EDID).EDID
[System.IO.File]::WriteAllBytes("edid-name.bin", $edid)
```

## Wireless transmitters: don't force the whole display EDID

If your setup goes through a wireless HDMI transmitter (or any other
extender), **don't** just force the real display's full EDID - its video
timings reflect what the *display* supports, not what the transmitter can
actually carry, and forcing a mode the transmitter can't sync to produces a
black screen (ask us how we know).

Instead, build a hybrid EDID: keep the transmitter's own (already-working)
video timings untouched, and only splice in the real display's audio
capability block.

Run [kodi-edid-hybrid.sh](../../kodi-edid-hybrid.sh) (repo root):

```bash
bash kodi-edid-hybrid.sh
```

It lets you pick the video and audio sources from a menu, and each pick can
be either an existing `.bin` file or a **live capture straight off a
connector right now** (e.g. what the transmitter is currently advertising,
with everything connected as usual - server -> transmitter -> receiver ->
display, no override active). So for the transmitter side you typically
don't need to capture anything by hand first; just pick "capture live" for
the connector when prompted for the video source. You'd still capture the
real display's EDID separately for the audio side (see above), since that
needs the display connected directly, bypassing the transmitter.

It builds the merged file as `<audio-source-name>_hybrid.bin` and can hand
off straight to `kodi-edid-setup.sh` to apply it.

If you'd rather script the merge yourself instead of the interactive
picker, [scripts/edid-merge.py](../../scripts/edid-merge.py) takes two
existing files directly:

```bash
python3 scripts/edid-merge.py \
    --video kodi/edid-overrides/transmitter-normal.bin \
    --audio kodi/edid-overrides/aurora-pro.bin \
    --output kodi/edid-overrides/aurora-pro_hybrid.bin
```

Either way, apply the resulting hybrid file (not the raw display capture)
with `kodi-edid-setup.sh`.

These files are machine-specific (tied to your actual display/transmitter
hardware), so they're gitignored — this README is here just to keep the
directory present in checkouts.

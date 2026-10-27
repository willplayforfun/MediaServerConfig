# Display and HDMI audio

Display path: server HDMI → wireless HDMI transmitter stick → receiver → projector. The transmitter's EDID name is `TuTuLink`; it's powered from a server USB port, and the receiver is wall-powered.

Run `host/display-diagnose.sh` (as root) for a read-only snapshot of connector state, the active mode, audio ELD, and kernel messages.

## Transmitter overheating (picture flapping)

- **Symptom:** the projector cycles every few seconds between the transmitter's "unconnected" screen and the picture. The server sees the connector as steadily connected, and the plain console flaps too.
- **Cause:** the transmitter overheats after sending nonstop for days. Unplugging it for a few minutes to cool down fixes it.
- **Requirement:** anything that drives the display must let it go dark when idle.
- Blanking the console turns the HDMI output off (`/sys/class/drm/card0-HDMI-A-1/dpms` reads `Off`):
  - Blank: `setterm --term linux --blank force < /dev/tty1`
  - Wake: `setterm --term linux --blank poke < /dev/tty1`
- It's unconfirmed whether the transmitter fully cools with no signal but power still on. If it doesn't, the fallback is a USB hub with per-port power switching (`uhubctl`).

## HDMI audio boot race

- **Symptoms:**
  - Video works, and `edid-decode` shows audio support.
  - Every `/proc/asound/card*/eld#*` reads `eld_valid 0`.
  - `speaker-test` on the `hdmi:` devices is silent, with channels listed as "Unknown".
  - dmesg shows `snd_hda_codec_intelhdmi … HDMI: pin NID 0x7 not registered`.
- **Cause:** the HDA codec probes before display init finishes, so only some pins are registered. A broken boot shows 3 `eld#2.*` entries; a healthy one shows 9 (3 pins × 3 devices). i915's "display connected" notifications for pin 0x07 are then dropped.
- **Ruled out:**
  - Pin config: all three pins read `[Jack] Digital Out at Int HDMI`.
  - The `force_connect` quirk.
  - `snd_intel_dspcfg.dsp_driver=1`: the system already uses the legacy HDA driver.
  - A `softdep snd_hda_intel pre: i915` load-order fix: tested, didn't help.
- **Fix (confirmed across reboots):** a PCI remove/rescan of the HDA controller after boot. Once fixed, `eld#2.6` shows `TuTuLink` with `eld_valid 1`.
  - `host/install-hdmi-audio-fix.sh` installs this as a systemd oneshot (`hdmi-audio-reprobe.service`) that runs before Docker.
  - The script also offers the softdep option for other hardware.
  - Manual equivalent: `echo 1 > /sys/bus/pci/devices/0000:00:1f.3/remove; echo 1 > /sys/bus/pci/rescan`

## Dead ends

- **EDID overrides.** The original "no audio" diagnosis blamed the transmitter's EDID. In fact its EDID already advertises audio (Basic audio plus an Audio Data Block). The EDID override and merge tooling was removed.

## Gotchas

- `/sys/class/drm/*/edid` always stats as 0 bytes, so measure it by reading it: `cat … | wc -c`.
- debugfs connector overrides (`edid_override`, `force`) don't survive a reboot.
- The kernel doesn't log hotplug events, so an empty dmesg grep doesn't mean nothing happened.

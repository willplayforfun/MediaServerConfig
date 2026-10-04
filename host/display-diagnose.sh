#!/bin/bash
# display-diagnose.sh
# Read-only snapshot of the server's display output: DRM connector state
# (sysfs + debugfs override/force), the active mode, HDMI audio ELD, the TV
# launcher containers and their logs, HDMI audio activity, and kernel
# messages. Ends by sampling the connector status for 20 seconds.
#
# Changes nothing. Useful for debugging via AI.
#
# Usage:
#   sudo bash host/display-diagnose.sh

set -u

section() { printf '\n===== %s =====\n' "$1"; }

if [ "$(id -u)" -ne 0 ]; then
    echo "Run as root (debugfs + dmesg need it): sudo bash $0" >&2
    exit 1
fi

section "host"
date
uptime
uname -r
echo "cmdline: $(cat /proc/cmdline)"

section "kernel EDID/video params"
for p in /sys/module/drm/parameters/edid_firmware /sys/module/drm_kms_helper/parameters/edid_firmware; do
    [ -e "$p" ] && echo "$p = $(cat "$p")"
done
ls -la /lib/firmware/edid 2>/dev/null || echo "(no /lib/firmware/edid)"

section "DRM connectors (sysfs)"
for d in /sys/class/drm/card*-*/; do
    [ -f "${d}status" ] || continue
    name="$(basename "$d")"
    # sysfs binary attributes always stat as 0 bytes, so measure by reading
    edid_len="$(cat "${d}edid" 2>/dev/null | wc -c)"
    edid_md5="none"
    [ "$edid_len" -gt 0 ] && edid_md5="$(md5sum < "${d}edid" | cut -c1-12) (${edid_len} bytes)"
    echo "$name: status=$(cat "${d}status") enabled=$(cat "${d}enabled" 2>/dev/null) edid=$edid_md5"
    echo "  modes: $(head -n 8 "${d}modes" 2>/dev/null | tr '\n' ' ')"
done

section "active display mode (i915)"
for f in /sys/kernel/debug/dri/*/i915_display_info; do
    [ -e "$f" ] || continue
    grep -iE 'crtc|mode:|hdmi|active=' "$f" | head -n 20
    break
done

section "HDMI audio ELD (what the sink says it can play)"
# monitor_present/eld_valid=1 with sad_count>0 means the connected display
# advertises audio and the audio driver has registered that HDMI port.
for f in /proc/asound/card*/eld#*; do
    [ -e "$f" ] || continue
    echo "-- $f"
    grep -E 'monitor_present|eld_valid|monitor_name|sad_count|sad[0-9]+_coding_type|sad[0-9]+_channels|sad[0-9]+_rates' "$f"
done

section "DRM connectors (debugfs override/force)"
if [ -d /sys/kernel/debug/dri ]; then
    for c in /sys/kernel/debug/dri/*/*/; do
        [ -e "${c}edid_override" ] || continue
        ov_size="$(wc -c < "${c}edid_override" 2>/dev/null || echo ?)"
        ov_md5="-"
        [ "$ov_size" != "0" ] && [ "$ov_size" != "?" ] && ov_md5="$(md5sum < "${c}edid_override" | cut -c1-12)"
        echo "$c"
        echo "  force=$(cat "${c}force" 2>/dev/null)  edid_override=${ov_size} bytes md5=${ov_md5}"
    done
else
    echo "debugfs not mounted"
fi

section "display containers"
for c in tv-hub tv-home tv-youtube kodi; do
    if docker inspect "$c" >/dev/null 2>&1; then
        docker inspect -f "$c: status={{.State.Status}} running={{.State.Running}} restarts={{.RestartCount}} started={{.State.StartedAt}} exit={{.State.ExitCode}} oom={{.State.OOMKilled}}" "$c"
    else
        echo "$c: (no container)"
    fi
done

section "tv-hub log (last 40 lines)"
docker logs --tail 40 tv-hub 2>&1

for c in tv-home tv-youtube; do
    section "$c log (last 20 lines)"
    docker logs --tail 20 "$c" 2>&1
done

section "audio playing (HDMI PCM state)"
grep -H "state:" /proc/asound/card*/pcm*p/sub*/status 2>/dev/null || echo "(no PCM status files)"

section "console blank state"
for d in /sys/class/drm/card*-*/; do
    [ -f "${d}dpms" ] && echo "$(basename "$d"): dpms=$(cat "${d}dpms")"
done

section "kernel messages (drm/hdmi/hotplug, last 60)"
dmesg --ctime 2>/dev/null | grep -iE 'drm|i915|xe |hdmi|hotplug|hpd|edid|snd_hda|eld' | tail -n 60

section "20s connector sample (watching for server-side flaps)"
prev=""
for _ in $(seq 1 40); do
    cur=""
    for d in /sys/class/drm/card*-*/; do
        [ -f "${d}status" ] || continue
        cur+="$(basename "$d")=$(cat "${d}status")/$(cat "${d}enabled" 2>/dev/null) "
    done
    if [ "$cur" != "$prev" ]; then
        echo "$(date +%T.%N | cut -c1-12) $cur"
        prev="$cur"
    fi
    sleep 0.5
done
echo "(sampling done - only changes are printed, so one line means no change)"
echo "(no change here while the picture drops out = the server kept its connection; the drop is"
echo " downstream, e.g. a cable, extender or the display itself)"

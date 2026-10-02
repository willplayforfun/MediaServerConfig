#!/bin/bash
# display-diagnose.sh
# Read-only snapshot of everything relevant to "the projector keeps dropping
# to the transmitter's 'unconnected' screen and coming back": DRM connector
# state (sysfs + debugfs override/force), Kodi container restarts, Kodi's
# own log, its display/audio settings, and kernel hotplug messages. Ends by
# sampling the connector status for 20 seconds so a server-side flap shows
# up as a status/mode change in the output.
#
# Changes nothing. Paste the full output back for diagnosis.
#
# Usage:
#   sudo bash scripts/display-diagnose.sh 2>&1 | tee display-diagnose.log

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
KODI_CFG="${REPO_DIR}/kodi/config"

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
# monitor_present/eld_valid=1 and sad_count>0 means the transmitter's EDID
# already advertises audio - i.e. no override needed for audio at all.
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
for c in kodi switcher youtube-tv; do
    if docker inspect "$c" >/dev/null 2>&1; then
        docker inspect -f "$c: status={{.State.Status}} running={{.State.Running}} restarts={{.RestartCount}} started={{.State.StartedAt}} exit={{.State.ExitCode}} oom={{.State.OOMKilled}}" "$c"
    else
        echo "$c: (no container)"
    fi
done

section "kodi container log (last 40 lines)"
docker logs --tail 40 kodi 2>&1

section "kodi.log (errors, display, audio)"
if [ -f "${KODI_CFG}/temp/kodi.log" ]; then
    grep -iE 'error|fatal|resolution|refresh|modeset|drm|gbm|hdmi|audio|sink|passthrough|crash' "${KODI_CFG}/temp/kodi.log" | tail -n 60
else
    echo "(no ${KODI_CFG}/temp/kodi.log)"
fi
[ -f "${KODI_CFG}/temp/kodi.old.log" ] && echo "(a kodi.old.log exists - Kodi has restarted at least once)"
ls -la "${KODI_CFG}"/temp/kodi_crashlog* 2>/dev/null

section "kodi display/audio settings"
if [ -f "${KODI_CFG}/userdata/guisettings.xml" ]; then
    grep -E 'id="(videoscreen|audiooutput|videoplayer\.adjustrefreshrate)' "${KODI_CFG}/userdata/guisettings.xml"
else
    echo "(no guisettings.xml)"
fi

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
echo "(no change here while the projector flaps = the drop is on the wireless TX/RX link,"
echo " not a hotplug the server sees - that points at the signal being sent, not the connection)"

#!/bin/bash
# kodi-edid-hybrid.sh
# Interactive wrapper around scripts/edid-merge.py: lets you pick which
# EDID supplies video timings and which supplies audio capability - either
# an existing captured .bin file, or a live capture read straight off a
# connector right now (e.g. what a transmitter is currently advertising) -
# builds the merged file into kodi/edid-overrides/, and optionally hands
# off straight to kodi-edid-setup.sh to apply it.
#
# See kodi/edid-overrides/README.md for why this two-source merge exists -
# short version: forcing a display's whole EDID onto a wireless transmitter
# can black out video if the transmitter can't carry the display's
# preferred mode, so the video timings and the audio capability need to
# come from two different sources.
#
# Usage:
#   bash kodi-edid-hybrid.sh
#
# Safe to re-run.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EDID_DIR="${SCRIPT_DIR}/kodi/edid-overrides"
MERGE_SCRIPT="${SCRIPT_DIR}/scripts/edid-merge.py"
SETUP_SCRIPT="${SCRIPT_DIR}/kodi-edid-setup.sh"

if ! command -v python3 > /dev/null 2>&1; then
    echo "[kodi-edid-hybrid] python3 is required (used by edid-merge.py) but wasn't found on PATH." >&2
    exit 1
fi

# Reads the current EDID directly off a connector's sysfs attribute and
# saves it under EDID_DIR (sysfs edid files are normally world-readable, so
# this shouldn't need root, unlike kodi-edid-setup.sh's debugfs writes).
# Echoes the saved path on success; returns 1 without echoing on failure.
capture_connector() {
    local conn_sysfs_dir="$1"
    local conn_name
    conn_name="$(basename "$conn_sysfs_dir" | sed -E 's/^card[0-9]+-//')"
    local edid_attr="${conn_sysfs_dir}/edid"
    local default_name="${conn_name}-live.bin"
    local save_name save_path ow bytes

    if [ ! -r "$edid_attr" ]; then
        echo "  Can't read $edid_attr (permission denied, or this kernel doesn't expose it here)." >&2
        return 1
    fi

    read -r -p "  Save capture as [$default_name]: " save_name
    save_name="${save_name:-$default_name}"
    save_path="${EDID_DIR}/${save_name%.bin}.bin"

    if [ -e "$save_path" ]; then
        read -r -p "  $(basename "$save_path") already exists, overwrite? [y/N] " ow
        if ! [[ "$ow" =~ ^[Yy] ]]; then
            echo "  Not overwriting, capture cancelled." >&2
            return 1
        fi
    fi

    cat "$edid_attr" > "$save_path"

    if [ ! -s "$save_path" ]; then
        rm -f "$save_path"
        echo "  $conn_name has no EDID data right now - is it actually connected and outputting? (see /sys/class/drm/$(basename "$conn_sysfs_dir")/status)" >&2
        return 1
    fi

    bytes="$(wc -c < "$save_path" | tr -d ' ')"
    echo "  Captured $bytes bytes from $conn_name -> $(basename "$save_path")" >&2
    echo "$save_path"
}

# Builds the combined pick-list for one prompt: every *.bin in EDID_DIR,
# plus a "capture live" entry per DRM connector. Populates the caller's
# src_kinds[]/src_refs[] arrays (kind is "file" or "connector"; ref is a
# file path or a /sys/class/drm/<connector> dir respectively).
build_source_list() {
    src_kinds=()
    src_refs=()

    shopt -s nullglob
    local f
    for f in "$EDID_DIR"/*.bin; do
        src_kinds+=("file")
        src_refs+=("$f")
    done
    shopt -u nullglob

    local d name status
    for d in /sys/class/drm/card*-*/; do
        [ -f "${d}status" ] || continue
        name="$(basename "$d" | sed -E 's/^card[0-9]+-//')"
        status="$(cat "${d}status" 2> /dev/null || echo unknown)"
        src_kinds+=("connector")
        src_refs+=("${d%/}|${name}|${status}")
    done
}

# Prints the menu built by build_source_list to stderr (never stdout - the
# caller captures pick_source's result via command substitution, and
# anything on stdout here would silently corrupt that capture).
list_sources() {
    local i kind ref name status
    for i in "${!src_kinds[@]}"; do
        kind="${src_kinds[$i]}"
        ref="${src_refs[$i]}"
        if [ "$kind" = "file" ]; then
            printf "  %d) %s\n" "$((i + 1))" "$(basename "$ref")" >&2
        else
            name="${ref#*|}"; name="${name%%|*}"
            status="${ref##*|}"
            printf "  %d) [capture live] %s (%s)\n" "$((i + 1))" "$name" "$status" >&2
        fi
    done
}

# Prompts to pick one entry from the current src_kinds[]/src_refs[] (set by
# build_source_list), resolving a "connector" pick into an actual capture.
# Echoes the resulting file path on success; returns 1 on invalid input or
# a cancelled/failed capture.
pick_source() {
    local prompt="$1"
    local choice idx kind ref

    list_sources
    read -r -p "$prompt " choice

    if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt "${#src_kinds[@]}" ]; then
        return 1
    fi

    idx=$((choice - 1))
    kind="${src_kinds[$idx]}"
    ref="${src_refs[$idx]}"

    if [ "$kind" = "file" ]; then
        echo "$ref"
    else
        capture_connector "${ref%%|*}"
    fi
}

build_source_list
if [ ${#src_kinds[@]} -eq 0 ]; then
    echo "[kodi-edid-hybrid] No .bin files in $EDID_DIR and no DRM connectors found under /sys/class/drm/. Nothing to work with." >&2
    exit 1
fi

echo "[kodi-edid-hybrid] Which one has the VIDEO timings you want to keep (e.g. what the transmitter itself normally advertises)?"
if ! video_file="$(pick_source "  Video source:")"; then
    echo "[kodi-edid-hybrid] Not a valid selection (or the capture failed/was cancelled), aborting." >&2
    exit 1
fi

# Rebuild the source list so a file just captured for the video pick shows
# up as a normal file option here too, and exclude whichever file the
# video pick resolved to so you can't merge a file with itself.
build_source_list
filtered_kinds=()
filtered_refs=()
for i in "${!src_kinds[@]}"; do
    if [ "${src_kinds[$i]}" = "file" ] && [ "${src_refs[$i]}" = "$video_file" ]; then
        continue
    fi
    filtered_kinds+=("${src_kinds[$i]}")
    filtered_refs+=("${src_refs[$i]}")
done
src_kinds=("${filtered_kinds[@]}")
src_refs=("${filtered_refs[@]}")

if [ ${#src_kinds[@]} -eq 0 ]; then
    echo "[kodi-edid-hybrid] No other sources to pull audio capability from." >&2
    exit 1
fi

echo
echo "Which one has the real AUDIO capability you want to add (e.g. a captured display EDID)?"
if ! audio_file="$(pick_source "  Audio source:")"; then
    echo "[kodi-edid-hybrid] Not a valid selection (or the capture failed/was cancelled), aborting." >&2
    exit 1
fi

audio_base="$(basename "$audio_file" .bin)"
default_output="${EDID_DIR}/${audio_base}_hybrid.bin"

echo
read -r -p "Output filename [$(basename "$default_output")]: " output_name
if [ -z "$output_name" ]; then
    output_file="$default_output"
else
    # Accept the name with or without a .bin the user typed themselves.
    output_file="${EDID_DIR}/${output_name%.bin}.bin"
fi

if [ -e "$output_file" ]; then
    read -r -p "$(basename "$output_file") already exists, overwrite? [y/N] " overwrite_ans
    if ! [[ "$overwrite_ans" =~ ^[Yy] ]]; then
        echo "[kodi-edid-hybrid] Aborting without overwriting." >&2
        exit 1
    fi
fi

echo
echo "[kodi-edid-hybrid] Merging $(basename "$video_file") (video) + $(basename "$audio_file") (audio) -> $(basename "$output_file")"
python3 "$MERGE_SCRIPT" --video "$video_file" --audio "$audio_file" --output "$output_file"

echo
read -r -p "Run kodi-edid-setup.sh now to apply $(basename "$output_file")? [y/N] " apply_ans
if [[ "$apply_ans" =~ ^[Yy] ]]; then
    exec sudo bash "$SETUP_SCRIPT"
fi

echo "[kodi-edid-hybrid] Done. Apply later with: sudo bash kodi-edid-setup.sh"

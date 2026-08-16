#!/bin/bash
# kodi-edid-hybrid.sh
# Interactive wrapper around scripts/edid-merge.py: lets you pick which
# captured EDID supplies video timings and which supplies audio capability,
# builds the merged file into kodi/edid-overrides/, and optionally hands off
# straight to kodi-edid-setup.sh to apply it.
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

shopt -s nullglob
files=("$EDID_DIR"/*.bin)
shopt -u nullglob

if [ ${#files[@]} -eq 0 ]; then
    echo "[kodi-edid-hybrid] No .bin files in $EDID_DIR. Capture some EDIDs first (see kodi/edid-overrides/README.md)." >&2
    exit 1
fi

# Prints a numbered menu of the given files to stderr (NOT stdout - callers
# capture pick_file's return value via command substitution, and anything
# written to stdout here would silently corrupt that capture).
list_files() {
    local arr=("$@")
    for i in "${!arr[@]}"; do
        printf "  %d) %s\n" "$((i + 1))" "$(basename "${arr[$i]}")" >&2
    done
}

# Prints a menu for the given files, prompts to pick one by number, and
# echoes the chosen path on success (intended to be captured via `x="$(pick_file ...)"`).
# Returns 1 without echoing anything if the input isn't a valid choice.
pick_file() {
    local prompt="$1"; shift
    local arr=("$@")
    local choice

    list_files "${arr[@]}"
    read -r -p "$prompt " choice

    if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt "${#arr[@]}" ]; then
        return 1
    fi
    echo "${arr[$((choice - 1))]}"
}

echo "[kodi-edid-hybrid] EDID files in $EDID_DIR:"
echo
echo "Which one has the VIDEO timings you want to keep (e.g. what the transmitter itself normally advertises)?"
if ! video_file="$(pick_file "  Video source:" "${files[@]}")"; then
    echo "[kodi-edid-hybrid] Not a valid selection, aborting." >&2
    exit 1
fi

# Offer every file except the one just picked, so you can't accidentally
# merge a file with itself.
audio_candidates=()
for f in "${files[@]}"; do
    [ "$f" = "$video_file" ] || audio_candidates+=("$f")
done

if [ ${#audio_candidates[@]} -eq 0 ]; then
    echo "[kodi-edid-hybrid] No other .bin files to pull audio capability from." >&2
    exit 1
fi

echo
echo "Which one has the real AUDIO capability you want to add (e.g. a captured display EDID)?"
if ! audio_file="$(pick_file "  Audio source:" "${audio_candidates[@]}")"; then
    echo "[kodi-edid-hybrid] Not a valid selection, aborting." >&2
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

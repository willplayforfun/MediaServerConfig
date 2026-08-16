#!/bin/bash
# kodi-add-youtube-favourite.sh
# Pre-seeds a "YouTube" favourite into Kodi's favourites.xml that tells the
# switcher to stop Kodi and start the youtube-tv kiosk browser. Kodi has no
# first-run wizard to hang this on (modern Kodi boots straight to defaults,
# no setup flow at all - see OperationsGuide.md), so this writes the file
# directly instead of requiring it to be typed in through Kodi's on-screen
# keyboard via the remote.
#
# Safe to re-run: no-ops if the favourite is already present. Merges into an
# existing favourites.xml (e.g. one with favourites added by hand through
# Kodi's UI) rather than overwriting it.
#
# Usage:
#   bash kodi-add-youtube-favourite.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
USERDATA_DIR="${SCRIPT_DIR}/kodi/config/userdata"
FAVOURITES_FILE="${USERDATA_DIR}/favourites.xml"

FAVOURITE_ACTION='System.Exec("curl -s -X POST http://switcher:8099/switch/youtube-tv")'
FAVOURITE_LINE="    <favourite name=\"YouTube\" thumb=\"\">${FAVOURITE_ACTION}</favourite>"

mkdir -p "${USERDATA_DIR}"

if [ -f "${FAVOURITES_FILE}" ] && grep -qF 'switch/youtube-tv' "${FAVOURITES_FILE}"; then
    echo "[kodi-add-youtube-favourite] Already present in ${FAVOURITES_FILE}. Nothing to do."
    exit 0
fi

if [ -f "${FAVOURITES_FILE}" ] && grep -qF '</favourites>' "${FAVOURITES_FILE}"; then
    # Insert just before the closing tag, preserving whatever favourites
    # Kodi (or a previous run of this script) already wrote.
    sed -i "s#</favourites>#${FAVOURITE_LINE}\n</favourites>#" "${FAVOURITES_FILE}"
    echo "[kodi-add-youtube-favourite] Added to existing ${FAVOURITES_FILE}."
elif [ -f "${FAVOURITES_FILE}" ]; then
    echo "[kodi-add-youtube-favourite] ${FAVOURITES_FILE} exists but has no </favourites> closing tag - not touching it." >&2
    echo "[kodi-add-youtube-favourite] Add this favourite manually instead:" >&2
    echo "  ${FAVOURITE_LINE}" >&2
    exit 1
else
    cat > "${FAVOURITES_FILE}" <<EOF
<favourites>
${FAVOURITE_LINE}
</favourites>
EOF
    echo "[kodi-add-youtube-favourite] Created ${FAVOURITES_FILE}."
fi

echo "[kodi-add-youtube-favourite] If the kodi container is already running, restart it to pick this up."

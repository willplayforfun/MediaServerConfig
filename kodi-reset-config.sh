#!/bin/bash
# kodi-reset-config.sh
# Wipes kodi/config/ (bind-mounted to /root/.kodi, gitignored) so Kodi comes
# back up with a completely default profile - no interactive wizard to
# reset here (modern Kodi doesn't have one; it just boots straight to the
# default Estuary home screen), so this is for wiping out custom settings,
# addons, or a broken profile rather than "testing setup."
#
# This also deletes the seeded YouTube favourite (kodi/config/userdata/
# favourites.xml) - re-run kodi-add-youtube-favourite.sh afterward if you
# want it back.
#
# Stops the kodi container first if it's running, since Kodi holds files
# open under kodi/config/ and may write to it during shutdown.
#
# Usage:
#   bash kodi-reset-config.sh
#
# Safe to re-run (no-op if kodi/config/ is already gone).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="${SCRIPT_DIR}/kodi/config"

if [ ! -d "$CONFIG_DIR" ]; then
    echo "[kodi-reset-config] $CONFIG_DIR doesn't exist. Nothing to do."
    exit 0
fi

if docker inspect kodi >/dev/null 2>&1 && [ "$(docker inspect -f '{{.State.Running}}' kodi 2>/dev/null)" = "true" ]; then
    echo "[kodi-reset-config] Stopping the kodi container..."
    docker stop kodi >/dev/null
fi

echo "[kodi-reset-config] About to permanently delete $CONFIG_DIR"
read -r -p "Continue? [y/N] " confirm_ans
if [[ ! "$confirm_ans" =~ ^[Yy] ]]; then
    echo "[kodi-reset-config] Aborted."
    exit 0
fi

rm -rf "$CONFIG_DIR"
echo "[kodi-reset-config] Deleted $CONFIG_DIR. Next start will come up with Kodi's stock defaults."
echo "[kodi-reset-config] Run kodi-add-youtube-favourite.sh to restore the YouTube launcher favourite."

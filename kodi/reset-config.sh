#!/bin/bash
# reset-config.sh
# Wipes kodi/config/ so Kodi comes back up with a completely default profile.
#
# Stops the kodi container first if it's running.
#
# Usage:
#   bash kodi/reset-config.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="${SCRIPT_DIR}/config"

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

#!/bin/bash
# install-omv-extras.sh
# Installs the OMV-Extras plugin set into OpenMediaVault.
# Must be run as root on the OMV host.
#
# Usage:
#   sudo /opt/docker/install-omv-extras.sh

set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
    echo "Error: must be run as root (try: sudo $0)" >&2
    exit 1
fi

wget -O - https://github.com/OpenMediaVault-Plugin-Developers/installScript/raw/master/install | bash

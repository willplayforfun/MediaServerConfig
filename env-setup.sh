#!/bin/bash
# env-setup.sh
# Creates the .env file consumed by docker-compose.
#
# Usage:
#   ./env-setup.sh
#
# Safe to re-run; will ask before overwriting an existing .env.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/.env"

# --- Helpers ----------------------------------------------------------------
validate_ipv4() {
    [[ $1 =~ ^([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})$ ]] || return 1
    local a=${BASH_REMATCH[1]} b=${BASH_REMATCH[2]} c=${BASH_REMATCH[3]} d=${BASH_REMATCH[4]}
    (( a <= 255 && b <= 255 && c <= 255 && d <= 255 ))
}

is_private_ipv4() {
    validate_ipv4 "$1" || return 1
    [[ $1 =~ ^([0-9]+)\.([0-9]+)\. ]]
    local a=${BASH_REMATCH[1]} b=${BASH_REMATCH[2]}
    if (( a == 10 )); then return 0; fi
    if (( a == 172 && b >= 16 && b <= 31 )); then return 0; fi
    if (( a == 192 && b == 168 )); then return 0; fi
    return 1
}

if [ -f "$ENV_FILE" ]; then
    read -r -p ".env already exists at ${ENV_FILE}. Overwrite? [y/N] " confirm
    case "$confirm" in
        [yY]|[yY][eE][sS]) ;;
        *) echo "Aborted. Existing .env left untouched."; exit 0 ;;
    esac
fi

echo "Setting up server configuration."
echo "Output: ${ENV_FILE}"
echo

# --- CERTBOT_EMAIL ----------------------------------------------------------
# Used by Let's Encrypt for expiry notifications. Not shared publicly.
read -r -p "Email address for Let's Encrypt certificate notifications: " CERTBOT_EMAIL
while [ -z "${CERTBOT_EMAIL}" ]; do
    read -r -p "  Email cannot be empty. Try again: " CERTBOT_EMAIL
done

# --- NOIP_NAME --------------------------------------------------------------
# The DDNS hostname prefix, e.g. 'myserver' for 'myserver.ddns.net'.
read -r -p "DDNS hostname (the part BEFORE '.ddns.net', e.g. 'myserver'): " NOIP_NAME
while [ -z "${NOIP_NAME}" ]; do
    read -r -p "  Hostname cannot be empty. Try again: " NOIP_NAME
done

# --- NOIP_USERNAME ----------------------------------------------------------
# The DDNS Key username.
read -r -p "DDNS Key username: " NOIP_USERNAME
while [ -z "${NOIP_USERNAME}" ]; do
    read -r -p "  Username cannot be empty. Try again: " NOIP_USERNAME
done

# --- NOIP_PASSWORD ----------------------------------------------------------
# The DDNS Key password. Read silently.
while :; do
    read -r -s -p "DDNS Key password: " NOIP_PASSWORD
    echo
    if [ -n "${NOIP_PASSWORD}" ]; then
        break
    fi
    echo "  Password cannot be empty."
done

# --- NOIP_HOSTNAMES ---------------------------------------------------------
# 'all.ddnskey.com' is a No-IP wildcard token that tells the DUC to update
# every hostname associated with the DDNS key. 
NOIP_HOSTNAMES="all.ddnskey.com"

# --- LOCAL_IP ---------------------------------------------------------------
# The server's LAN IP. 
# Auto-detect by asking the kernel which source IP it uses to reach the
# internet. This is more reliable than guessing interface names (eth0,
# enp1s0, eno1, etc.)
DETECTED_IP="$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src") print $(i+1)}' || true)"

if [ -n "${DETECTED_IP}" ]; then
    read -r -p "Server LAN IP [${DETECTED_IP}]: " LOCAL_IP
    LOCAL_IP="${LOCAL_IP:-$DETECTED_IP}"
else
    echo "Could not auto-detect a LAN IP."
    read -r -p "Server LAN IP: " LOCAL_IP
fi

while true; do
    if [ -z "${LOCAL_IP}" ]; then
        read -r -p "  IP cannot be empty. Try again: " LOCAL_IP
        continue
    fi
    if ! validate_ipv4 "${LOCAL_IP}"; then
        read -r -p "  '${LOCAL_IP}' is not a valid IPv4 address. Try again: " LOCAL_IP
        continue
    fi
    if ! is_private_ipv4 "${LOCAL_IP}"; then
        echo "  Warning: '${LOCAL_IP}' is not in a private range"
        echo "  (10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16)."
        echo "  Pointing dnsmasq at a non-private IP for a LAN hostname is almost"
        echo "  always a mistake."
        read -r -p "  Use it anyway? [y/N] " confirm
        case "$confirm" in
            [yY]|[yY][eE][sS]) break ;;
            *) read -r -p "  Server LAN IP: " LOCAL_IP; continue ;;
        esac
    fi
    break
done

# --- DNS1 / DNS2 ------------------------------------------------------------
# Upstream resolvers used by dnsmasq for any hostname it doesn't have a local override for.
DNS1="1.1.1.1"
DNS2="8.8.8.8"

# --- Service selection ------------------------------------------------------
# Each media service can be toggled on or off. docker-compose reads
# COMPOSE_PROFILES from .env and only starts services whose profile is listed.
# Re-run this script (or edit COMPOSE_PROFILES in .env) to change the mix.
echo
echo "Select which services to enable (press Enter to accept the default):"

PROFILES=()
ask_service() {
    # $1 = profile name, $2 = description, $3 = default (Y or N)
    local name="$1" desc="$2" def="$3" prompt ans
    if [ "$def" = "Y" ]; then prompt="[Y/n]"; else prompt="[y/N]"; fi
    read -r -p "  Enable ${desc}? ${prompt} " ans
    ans="${ans:-$def}"
    case "$ans" in
        [yY]|[yY][eE][sS]) PROFILES+=("$name") ;;
    esac
}

ask_service jellyfin             "Jellyfin (video streaming)"                  Y
ask_service plex                 "Plex (video streaming)"                      N
ask_service universalmediaserver "Universal Media Server (DLNA, UPnP)"  N
ask_service navidrome            "Navidrome (music streaming)"                 Y
ask_service audiobookshelf       "Audiobookshelf (audiobooks & podcasts)"      Y
ask_service stash                "Stash (video streaming)"                                       N
ask_service filebrowser          "Filebrowser (web file manager)"             Y

if [ ${#PROFILES[@]} -eq 0 ]; then
    COMPOSE_PROFILES=""
    echo "  Warning: no services selected. Only infrastructure will start."
else
    COMPOSE_PROFILES="$(IFS=,; echo "${PROFILES[*]}")"
fi

# --- Plex configuration (only when enabled) ---------------------------------
PLEX_CLAIM=""
PLEX_HTTPS_PORT="8443"
case ",${COMPOSE_PROFILES}," in
    *,plex,*)
        echo
        echo "Plex is enabled."
        echo "  Get a claim token from https://www.plex.tv/claim (valid ~4 minutes)."
        read -r -p "  Plex claim token: " PLEX_CLAIM
        read -r -p "  Port (optional, press Enter to use default 8443): " PLEX_PORT_IN
        PLEX_HTTPS_PORT="${PLEX_PORT_IN:-8443}"
        echo "  Remember to forward external port ${PLEX_HTTPS_PORT} for remote access."
        ;;
esac

# --- Write .env -------------------------------------------------------------
umask 077
cat > "${ENV_FILE}" <<EOF
# Generated by env-setup.sh on $(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Let's Encrypt / Certbot
CERTBOT_EMAIL=${CERTBOT_EMAIL}
# Set STAGING=1 to test before requesting a real certificate.
# Remove or set to empty once you have confirmed cert issuance works.
STAGING=

# No-IP DDNS key configuration
NOIP_NAME=${NOIP_NAME}
NOIP_USERNAME=${NOIP_USERNAME}
NOIP_PASSWORD=${NOIP_PASSWORD}
NOIP_HOSTNAMES=${NOIP_HOSTNAMES}

# Server LAN IP
LOCAL_IP=${LOCAL_IP}

# Upstream DNS servers 
# Safe to edit; restart the dnsmasq container after changing.
DNS1=${DNS1}
DNS2=${DNS2}

# The root directory for the filebrowser web UI
FILEBROWSER_ROOT=/srv/mergerfs/media/share
# Initial password for Filebrowser admin
INITIAL_FILEBROWSER_PASSWORD=hellofilebrowser

# Which services to run (Docker Compose profiles). Comma-separated, no spaces.
# Edit this and re-run 'docker compose up -d' to change the active services.
COMPOSE_PROFILES=${COMPOSE_PROFILES}

# Plex
# One-time claim token (only for first setup).
PLEX_CLAIM=${PLEX_CLAIM}
PLEX_HTTPS_PORT=${PLEX_HTTPS_PORT}
EOF

chmod 600 "${ENV_FILE}"
echo "Wrote ${ENV_FILE} (mode 600)."

echo
echo "Public URL will be:   https://${NOIP_NAME}.ddns.net"
echo "Internal LAN target:  ${LOCAL_IP}"
echo "Enabled services:     ${COMPOSE_PROFILES:-<none>}"
case ",${COMPOSE_PROFILES}," in
    *,plex,*) echo "Plex URL:             https://${NOIP_NAME}.ddns.net:${PLEX_HTTPS_PORT}/web" ;;
esac


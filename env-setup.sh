#!/bin/bash
# env-setup.sh
# Creates or updates the .env file consumed by docker-compose.
#
# Usage:
#   ./env-setup.sh
#
# Safe to re-run; existing values are pre-filled as defaults so you can update
# one field by pressing Enter through the rest.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/.env"

# shellcheck source=env-lib.sh
source "${SCRIPT_DIR}/env-lib.sh"

# Seed all vars with defaults so write_env always has them defined.
CERTBOT_EMAIL=""
DNS_PROVIDER="none"
DOMAIN=""
NOIP_USERNAME=""
NOIP_PASSWORD=""
NOIP_HOSTNAMES=""
CF_API_TOKEN=""
LOCAL_IP=""
DNS1="1.1.1.1"
DNS2="8.8.8.8"
COMPOSE_PROFILES=""
PLEX_CLAIM=""
PLEX_HTTPS_PORT="8443"
FILEBROWSER_ROOT="/srv/mergerfs/media/share"
INITIAL_FILEBROWSER_PASSWORD="hellofilebrowser"

EXISTING_ENV=false
if [ -f "$ENV_FILE" ]; then
    EXISTING_ENV=true
    # shellcheck disable=SC1090
    set -a; source "${ENV_FILE}"; set +a
    echo "Loaded existing ${ENV_FILE}."
    echo "Press Enter at any prompt to keep the current value."
else
    echo "Setting up server configuration."
fi
echo "Output: ${ENV_FILE}"
echo

# Prompt for a value, showing the current value as the default.
# Usage: ask VARNAME "Prompt text"
# Sets VARNAME to the entered value, or keeps the existing value on Enter.
ask() {
    local _varname="$1" _prompt="$2" _current _ans
    _current="${!_varname}"
    if [ -n "$_current" ]; then
        read -r -p "${_prompt} [${_current}]: " _ans
        printf -v "$_varname" '%s' "${_ans:-$_current}"
    else
        read -r -p "${_prompt}: " _ans
        printf -v "$_varname" '%s' "$_ans"
    fi
}

# --- CERTBOT_EMAIL ----------------------------------------------------------
ask CERTBOT_EMAIL "Email address for Let's Encrypt certificate notifications"
while [ -z "${CERTBOT_EMAIL}" ]; do
    read -r -p "  Email cannot be empty. Try again: " CERTBOT_EMAIL
done

# --- DNS_PROVIDER -----------------------------------------------------------
echo
echo "DNS / DDNS provider:"
echo "  1) None       — no automatic DNS updates; you provide your full domain"
echo "  2) NoIP       — free DDNS hostname on ddns.net (e.g. myserver.ddns.net)"
echo "  3) Cloudflare — you own a domain managed on Cloudflare"

case "${DNS_PROVIDER}" in
    noip)       _dns_default=2 ;;
    cloudflare) _dns_default=3 ;;
    *)          _dns_default=1 ;;
esac
read -r -p "Select [1/2/3] [${_dns_default}]: " DNS_CHOICE
DNS_CHOICE="${DNS_CHOICE:-${_dns_default}}"
while [[ ! "${DNS_CHOICE}" =~ ^[123]$ ]]; do
    read -r -p "  Please enter 1, 2, or 3: " DNS_CHOICE
done

case "${DNS_CHOICE}" in
    1)
        DNS_PROVIDER="none"
        ask DOMAIN "Full public domain (e.g. home.example.com)"
        while [ -z "${DOMAIN}" ]; do
            read -r -p "  Domain cannot be empty. Try again: " DOMAIN
        done
        ;;
    2)
        DNS_PROVIDER="noip"
        # Extract the hostname portion from an existing .ddns.net DOMAIN.
        _noip_name="${DOMAIN%.ddns.net}"
        [ "$_noip_name" = "$DOMAIN" ] && _noip_name=""
        ask _noip_name "DDNS hostname (the part BEFORE '.ddns.net', e.g. 'myserver')"
        while [ -z "${_noip_name}" ]; do
            read -r -p "  Hostname cannot be empty. Try again: " _noip_name
        done
        DOMAIN="${_noip_name}.ddns.net"

        ask NOIP_USERNAME "DDNS Key username"
        while [ -z "${NOIP_USERNAME}" ]; do
            read -r -p "  Username cannot be empty. Try again: " NOIP_USERNAME
        done

        while :; do
            ask NOIP_PASSWORD "DDNS Key password"
            echo
            if [ -n "${NOIP_PASSWORD}" ]; then break; fi
            echo "  Password cannot be empty."
        done

        # 'all.ddnskey.com' is a No-IP wildcard token that tells the DUC to
        # update every hostname associated with the DDNS key.
        NOIP_HOSTNAMES="all.ddnskey.com"
        ;;
    3)
        DNS_PROVIDER="cloudflare"
        ask DOMAIN "Full public domain (e.g. home.example.com)"
        while [ -z "${DOMAIN}" ]; do
            read -r -p "  Domain cannot be empty. Try again: " DOMAIN
        done

        while :; do
            ask CF_API_TOKEN "Cloudflare API token (DNS edit permission for ${DOMAIN})"
            echo
            if [ -n "${CF_API_TOKEN}" ]; then break; fi
            echo "  Token cannot be empty."
        done
        ;;
esac

# --- LOCAL_IP ---------------------------------------------------------------
echo
DETECTED_IP="$(detect_local_ip)"
if [ -n "${DETECTED_IP}" ]; then
    echo "Detected LAN IP: ${DETECTED_IP}"
else
    echo "Could not auto-detect a LAN IP."
fi
# Prefer the saved value; fall back to the freshly detected IP.
LOCAL_IP="${LOCAL_IP:-$DETECTED_IP}"

if [ -n "${LOCAL_IP}" ]; then
    read -r -p "Server LAN IP [${LOCAL_IP}]: " _ip_input
    LOCAL_IP="${_ip_input:-$LOCAL_IP}"
else
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
DNS1="${DNS1:-1.1.1.1}"
DNS2="${DNS2:-8.8.8.8}"

# --- Service selection ------------------------------------------------------
echo
echo "Select which services to enable (press Enter to accept the default):"

PROFILES=()
ask_service() {
    # $1 = profile name, $2 = description, $3 = default (Y or N)
    local name="$1" desc="$2" def="$3" prompt ans
    # When updating an existing .env, derive the default from the saved profiles.
    if $EXISTING_ENV; then
        case ",${COMPOSE_PROFILES}," in
            *,"${name}",*) def="Y" ;;
            *) def="N" ;;
        esac
    fi
    if [ "$def" = "Y" ]; then prompt="[Y/n]"; else prompt="[y/N]"; fi
    read -r -p "  Enable ${desc}? ${prompt} " ans
    ans="${ans:-$def}"
    case "$ans" in
        [yY]|[yY][eE][sS]) PROFILES+=("$name") ;;
    esac
}

ask_service jellyfin             "Jellyfin (video streaming)"                Y
ask_service bazarr               "Bazarr (subtitle downloader & syncer)"     N
ask_service plex                 "Plex (video streaming)"                    N
ask_service universalmediaserver "Universal Media Server (DLNA, UPnP)"      N
ask_service navidrome            "Navidrome (music streaming)"               Y
ask_service audiobookshelf       "Audiobookshelf (audiobooks & podcasts)"    Y
ask_service stash                "Stash (video streaming)"                   N
ask_service filebrowser          "Filebrowser (web file manager)"            Y
ask_service calibrewebautomated  "Calibre-Web Automated (ebook library & reader)" N

# Add the DNS provider profile so the right DDNS container starts.
[ "${DNS_PROVIDER}" != "none" ] && PROFILES+=("${DNS_PROVIDER}")

if [ ${#PROFILES[@]} -eq 0 ]; then
    COMPOSE_PROFILES=""
    echo "  Warning: no services selected. Only infrastructure will start."
else
    COMPOSE_PROFILES="$(IFS=,; echo "${PROFILES[*]}")"
fi

# --- Plex configuration (only when enabled) ---------------------------------
PLEX_CLAIM="${PLEX_CLAIM:-}"
PLEX_HTTPS_PORT="${PLEX_HTTPS_PORT:-8443}"
case ",${COMPOSE_PROFILES}," in
    *,plex,*)
        echo
        echo "Plex is enabled."
        echo "  Get a claim token from https://www.plex.tv/claim (valid ~4 minutes)."
        ask PLEX_CLAIM "  Plex claim token"
        ask PLEX_HTTPS_PORT "  HTTPS port"
        PLEX_HTTPS_PORT="${PLEX_HTTPS_PORT:-8443}"
        echo "  Remember to forward external port ${PLEX_HTTPS_PORT} for remote access."
        ;;
esac

# --- Write .env -------------------------------------------------------------
FILEBROWSER_ROOT="${FILEBROWSER_ROOT:-/srv/mergerfs/media/share}"
INITIAL_FILEBROWSER_PASSWORD="${INITIAL_FILEBROWSER_PASSWORD:-hellofilebrowser}"
write_env "${ENV_FILE}"

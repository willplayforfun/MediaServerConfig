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
MEDIA_ROOT="/srv/mergerfs/media"
COMPOSE_PROFILES=""
PLEX_CLAIM=""
PLEX_HTTPS_PORT="8443"
FILEBROWSER_ROOT=""
INITIAL_FILEBROWSER_PASSWORD="hellofilebrowser"
UMS_NETWORK_INTERFACE=""
REMOTE_DEVICES=""
HOME_KEY="KEY_HOMEPAGE"
SLEEP_KEY=""
TV_AUDIO_DEVICE="hdmi:CARD=PCH,DEV=0"
INTERNAL_DNS_ADAPTER=""
OPNSENSE_URL=""
OPNSENSE_API_KEY=""
OPNSENSE_API_SECRET=""
OPNSENSE_TLS_VERIFY="false"

EXISTING_ENV=false
if [ -f "$ENV_FILE" ]; then
    EXISTING_ENV=true
    # shellcheck disable=SC1090
    set -a; source "${ENV_FILE}"; set +a
    # Carry the remote settings over from the Kodi-era variable names.
    if [ -z "${REMOTE_DEVICES}" ] && [ -n "${REMOTE_DEVICE:-}" ]; then
        REMOTE_DEVICES="${REMOTE_DEVICE}"
    fi
    if [ -n "${RETURN_KEY:-}" ] && [ "${HOME_KEY}" = "KEY_HOMEPAGE" ]; then
        HOME_KEY="${RETURN_KEY}"
    fi
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

# --- Internal DNS (router host override) -------------------------------------
echo
echo "Local DNS: how LAN clients resolve ${DOMAIN} to ${LOCAL_IP} (see README):"
echo "  1) Manual configuration"
echo "  2) Automatic configuration: OPNsense"

case "${INTERNAL_DNS_ADAPTER}" in
    opnsense) _idns_default=2 ;;
    *)        _idns_default=1 ;;
esac
read -r -p "Select [1/2] [${_idns_default}]: " IDNS_CHOICE
IDNS_CHOICE="${IDNS_CHOICE:-${_idns_default}}"
while [[ ! "${IDNS_CHOICE}" =~ ^[12]$ ]]; do
    read -r -p "  Please enter 1 or 2: " IDNS_CHOICE
done

if [ "${IDNS_CHOICE}" = "2" ]; then
    INTERNAL_DNS_ADAPTER="opnsense"
    echo " API key + secret: create under System > Access > Users > (user) > Ticket icon ("Create and download API keys"). "
    echo " The account needs these privileges:  "
    echo " - Services: Unbound DNS' "
    echo " - Services: Unbound DNS: Access Lists' "
    echo " - Services: Unbound DNS: Edit Host and Domain Override' "
    echo " - Services: Unbound DNS: General' "

    ask OPNSENSE_URL "  OPNsense web UI URL (e.g. https://192.168.1.1)"
    while [ -z "${OPNSENSE_URL}" ]; do
        read -r -p "  URL cannot be empty. Try again: " OPNSENSE_URL
    done

    ask OPNSENSE_API_KEY "  OPNsense API key"
    while [ -z "${OPNSENSE_API_KEY}" ]; do
        read -r -p "  API key cannot be empty. Try again: " OPNSENSE_API_KEY
    done

    ask OPNSENSE_API_SECRET "  OPNsense API secret"
    while [ -z "${OPNSENSE_API_SECRET}" ]; do
        read -r -p "  API secret cannot be empty. Try again: " OPNSENSE_API_SECRET
    done

    _tls_def="N"
    [ "${OPNSENSE_TLS_VERIFY}" = "true" ] && _tls_def="Y"
    if [ "${_tls_def}" = "Y" ]; then _tls_prompt="[Y/n]"; else _tls_prompt="[y/N]"; fi
    read -r -p "  Verify the router's TLS certificate? (N for self-signed) ${_tls_prompt} " _tls_ans
    _tls_ans="${_tls_ans:-${_tls_def}}"
    case "${_tls_ans}" in
        [yY]|[yY][eE][sS]) OPNSENSE_TLS_VERIFY="true" ;;
        *)                 OPNSENSE_TLS_VERIFY="false" ;;
    esac
else
    INTERNAL_DNS_ADAPTER=""
fi

# --- DNS1 / DNS2 ------------------------------------------------------------
DNS1="${DNS1:-1.1.1.1}"
DNS2="${DNS2:-8.8.8.8}"

# --- MEDIA_ROOT -------------------------------------------------------------
echo
ask MEDIA_ROOT "Media pool path (the folder holding movies/, tv/, music/, ...)"
while [ -z "${MEDIA_ROOT}" ]; do
    read -r -p "  Path cannot be empty. Try again: " MEDIA_ROOT
done
MEDIA_ROOT="${MEDIA_ROOT%/}"
if [ ! -d "${MEDIA_ROOT}" ]; then
    echo "  Note: ${MEDIA_ROOT} doesn't exist yet - create the mergerfs pool before"
    echo "  starting the stack."
fi

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
ask_service plex                 "Plex (video streaming)"                    N
ask_service universalmediaserver "Universal Media Server (DLNA, UPnP)"      N
ask_service navidrome            "Navidrome (music streaming)"               Y
ask_service audiobookshelf       "Audiobookshelf (audiobooks & podcasts)"    Y
ask_service stash                "Stash (video streaming)"                   N
ask_service filebrowser          "Filebrowser (web file manager)"            Y
ask_service fileflows            "FileFlows (media file processing workflows)"    N

# HDMI display app - at most one, since both drive the server's HDMI output
# directly and would fight over it. Defaults to whichever is already enabled.
case ",${COMPOSE_PROFILES}," in
    *,tv,*)   _display_default=2 ;;
    *,kodi,*) _display_default=3 ;;
    *)        _display_default=1 ;;
esac
echo
echo "  HDMI display app, for a TV/projector plugged into the server (pick one):"
echo "    1) None"
echo "    2) TV launcher (smart-TV home screen with app tiles, sleeps when idle)"
echo "    3) Kodi (media center)"
read -r -p "  Choice [${_display_default}]: " _display_choice
_display_choice="${_display_choice:-$_display_default}"
while ! [[ "$_display_choice" =~ ^[123]$ ]]; do
    read -r -p "  Please enter 1, 2 or 3: " _display_choice
done
case "$_display_choice" in
    2) PROFILES+=("tv") ;;
    3) PROFILES+=("kodi") ;;
esac

# Add the DNS provider profile so the right DDNS container starts.
[ "${DNS_PROVIDER}" != "none" ] && PROFILES+=("${DNS_PROVIDER}")

if [ ${#PROFILES[@]} -eq 0 ]; then
    COMPOSE_PROFILES=""
    echo "  Warning: no services selected. Only infrastructure will start."
else
    COMPOSE_PROFILES="$(IFS=,; echo "${PROFILES[*]}")"
fi

# --- UMS network interface (only when enabled) ------------------------------
case ",${COMPOSE_PROFILES}," in
    *,universalmediaserver,*)
        echo
        echo "Universal Media Server is enabled."
        echo "  Its DLNA/UPnP discovery must bind to the host's real LAN interface."
        _detected_iface="$(detect_local_interface)"
        UMS_NETWORK_INTERFACE="${UMS_NETWORK_INTERFACE:-$_detected_iface}"
        ask UMS_NETWORK_INTERFACE "  LAN network interface name"
        while ! interface_exists "${UMS_NETWORK_INTERFACE}"; do
            read -r -p "  '${UMS_NETWORK_INTERFACE}' was not found on this host (see 'ip addr'). Try again: " UMS_NETWORK_INTERFACE
        done
        ;;
esac

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

# --- TV launcher remote & audio (only when enabled) --------------------------
case ",${COMPOSE_PROFILES}," in
    *,tv,*)
        echo
        echo "TV launcher is enabled. The hub reads the remote directly: its Home"
        echo "button returns to the launcher (hold it to turn the display off), and"
        echo "any button wakes the display. If you don't know the remote's device"
        echo "or its Home button's key name yet, run 'sudo evtest' in another"
        echo "terminal first."
        echo

        shopt -s nullglob
        _remote_candidates=(/dev/input/by-id/*-event-*)
        shopt -u nullglob

        if [ ${#_remote_candidates[@]} -eq 0 ]; then
            echo "  No devices found under /dev/input/by-id/ - the hub will watch every"
            echo "  input device. Re-run this once the remote is plugged in to narrow it."
        else
            echo "  Available input devices:"
            for i in "${!_remote_candidates[@]}"; do
                printf "    %d) %s\n" "$((i + 1))" "${_remote_candidates[$i]}"
            done
            echo "  Current: ${REMOTE_DEVICES:-all devices}"
            while true; do
                read -r -p "  Remote's device numbers, space-separated (Enter = keep current, 'all' = every device): " _sel
                case "$_sel" in
                    "") break ;;
                    all) REMOTE_DEVICES=""; break ;;
                esac
                _picked=()
                _ok=true
                for _n in $_sel; do
                    if [[ "$_n" =~ ^[0-9]+$ ]] && [ "$_n" -ge 1 ] && [ "$_n" -le ${#_remote_candidates[@]} ]; then
                        _picked+=("${_remote_candidates[$((_n - 1))]}")
                    else
                        echo "  '$_n' isn't one of the listed numbers."
                        _ok=false
                    fi
                done
                if $_ok; then
                    REMOTE_DEVICES="$(IFS=,; echo "${_picked[*]}")"
                    break
                fi
            done
        fi

        ask HOME_KEY "  Key name evtest reported for the remote's Home button (or its numeric code)"
        while [ -z "${HOME_KEY}" ]; do
            read -r -p "  Key name cannot be empty. Try again: " HOME_KEY
        done
        ask SLEEP_KEY "  Optional button that turns the display off straight away (Enter to skip)"
        if command -v aplay >/dev/null 2>&1; then
            echo "  HDMI audio devices on this host (with the TV apps stopped, test one with"
            echo "  'speaker-test -D <device> -c 2 -t sine -l 1'):"
            aplay -L 2>/dev/null | grep '^hdmi:' | sed 's/^/    /' || echo "    (none found)"
        fi
        ask TV_AUDIO_DEVICE "  ALSA device for HDMI audio"
        ;;
esac

# --- Write .env -------------------------------------------------------------
FILEBROWSER_ROOT="${FILEBROWSER_ROOT:-${MEDIA_ROOT}/share}"
INITIAL_FILEBROWSER_PASSWORD="${INITIAL_FILEBROWSER_PASSWORD:-hellofilebrowser}"
write_env "${ENV_FILE}"

# --- Create tv-apps containers (only when the TV launcher is enabled) --------
# `compose up` never starts the "tv-apps" profile, so the hub needs them
# created once.
case ",${COMPOSE_PROFILES}," in
    *,tv,*)
        echo
        read -r -p "Create the tv-apps containers now (required before the launcher can show anything)? [Y/n] " _create_ans
        _create_ans="${_create_ans:-Y}"
        case "$_create_ans" in
            [yY]|[yY][eE][sS])
                if ! command -v docker >/dev/null 2>&1; then
                    echo "  Warning: docker not found on PATH. Run this manually later:" >&2
                    echo "    docker compose --profile tv-apps create" >&2
                elif ( cd "${SCRIPT_DIR}" && docker compose --profile tv-apps create ); then
                    echo "  tv-apps containers created."
                else
                    echo "  Warning: container creation failed. Run this manually once it's fixed:" >&2
                    echo "    docker compose --profile tv-apps create" >&2
                fi
                ;;
            *)
                echo "  Skipped. Run 'docker compose --profile tv-apps create' before using the launcher."
                ;;
        esac
        ;;
esac

# --- Remove the display app that isn't enabled -------------------------------
# Disabling a profile leaves its containers behind, and the TV launcher and
# Kodi would fight over the display.
case ",${COMPOSE_PROFILES}," in
    *,tv,*)   _retire=(kodi) ;;
    *,kodi,*) _retire=(tv-hub tv-home tv-youtube) ;;
    *)        _retire=(kodi tv-hub tv-home tv-youtube) ;;
esac
if command -v docker >/dev/null 2>&1; then
    _existing=()
    for _c in "${_retire[@]}"; do
        docker inspect "$_c" >/dev/null 2>&1 && _existing+=("$_c")
    done
    if [ ${#_existing[@]} -gt 0 ]; then
        echo
        read -r -p "Remove the containers of the display app you didn't pick (${_existing[*]})? [Y/n] " _rm_ans
        case "${_rm_ans:-Y}" in
            [yY]|[yY][eE][sS]) docker rm -f "${_existing[@]}" >/dev/null && echo "  Removed: ${_existing[*]}" ;;
            *) echo "  Kept. They'll fight over the display if both run - remove them with: docker rm -f ${_existing[*]}" ;;
        esac
    fi
fi

#!/bin/bash
# env-setup.sh
# Creates or updates the .env file consumed by docker compose. Each optional
# service's own questions live in its <service>/env.sh.
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

# Seed the core settings so write_env always has them defined.
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
    echo "Loaded existing ${ENV_FILE}."
    echo "Press Enter at any prompt to keep the current value."
else
    echo "Setting up server configuration."
fi
echo "Output: ${ENV_FILE}"
echo

# --- CERTBOT_EMAIL ----------------------------------------------------------
ask_required CERTBOT_EMAIL "Email address for Let's Encrypt certificate notifications"

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
pick DNS_CHOICE 3 "${_dns_default}"

case "${DNS_CHOICE}" in
    1)
        DNS_PROVIDER="none"
        ask_required DOMAIN "Full public domain (e.g. home.example.com)"
        ;;
    2)
        DNS_PROVIDER="noip"
        # Extract the hostname portion from an existing .ddns.net DOMAIN.
        _noip_name="${DOMAIN%.ddns.net}"
        [ "$_noip_name" = "$DOMAIN" ] && _noip_name=""
        ask_required _noip_name "DDNS hostname (the part BEFORE '.ddns.net', e.g. 'myserver')"
        DOMAIN="${_noip_name}.ddns.net"
        ask_required NOIP_USERNAME "DDNS Key username"
        ask_required NOIP_PASSWORD "DDNS Key password"
        # 'all.ddnskey.com' is a No-IP wildcard token that tells the DUC to
        # update every hostname associated with the DDNS key.
        NOIP_HOSTNAMES="all.ddnskey.com"
        ;;
    3)
        DNS_PROVIDER="cloudflare"
        ask_required DOMAIN "Full public domain (e.g. home.example.com)"
        ask_required CF_API_TOKEN "Cloudflare API token (DNS edit permission for ${DOMAIN})"
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
ask LOCAL_IP "Server LAN IP"

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
        confirm "  Use it anyway?" N && break
        read -r -p "  Server LAN IP: " LOCAL_IP
        continue
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
pick IDNS_CHOICE 2 "${_idns_default}"

if [ "${IDNS_CHOICE}" = "2" ]; then
    INTERNAL_DNS_ADAPTER="opnsense"
    echo "  API key + secret: create under System > Access > Users > (user) > Ticket icon"
    echo "  (\"Create and download API keys\"). The account needs these privileges:"
    echo "  - Services: Unbound DNS"
    echo "  - Services: Unbound DNS: Access Lists"
    echo "  - Services: Unbound DNS: Edit Host and Domain Override"
    echo "  - Services: Unbound DNS: General"

    ask_required OPNSENSE_URL "  OPNsense web UI URL (e.g. https://192.168.1.1)"
    ask_required OPNSENSE_API_KEY "  OPNsense API key"
    ask_required OPNSENSE_API_SECRET "  OPNsense API secret"

    _tls_default="N"
    [ "${OPNSENSE_TLS_VERIFY}" = "true" ] && _tls_default="Y"
    if confirm "  Verify the router's TLS certificate? (N for self-signed)" "${_tls_default}"; then
        OPNSENSE_TLS_VERIFY="true"
    else
        OPNSENSE_TLS_VERIFY="false"
    fi
else
    INTERNAL_DNS_ADAPTER=""
fi

# --- DNS1 / DNS2 ------------------------------------------------------------
DNS1="${DNS1:-1.1.1.1}"
DNS2="${DNS2:-8.8.8.8}"

# --- MEDIA_ROOT -------------------------------------------------------------
echo
ask_required MEDIA_ROOT "Media pool path (the folder holding movies/, tv/, music/, ...)"
MEDIA_ROOT="${MEDIA_ROOT%/}"
if [ ! -d "${MEDIA_ROOT}" ]; then
    echo "  Note: ${MEDIA_ROOT} doesn't exist yet - create the mergerfs pool before"
    echo "  starting the stack."
fi

# --- Service selection ------------------------------------------------------
run_hooks defaults all

echo
echo "Select which services to enable (press Enter to accept the default):"

PROFILES=()
DISPLAY_APPS=()
for name in "${SERVICES[@]}"; do
    if [ "${SERVICE_GROUP[$name]}" = "display" ]; then
        DISPLAY_APPS+=("$name")
        continue
    fi
    # When updating an existing .env, default to what's enabled now.
    _default="${SERVICE_DEFAULT[$name]}"
    if $EXISTING_ENV; then
        if profile_enabled "$name"; then _default="Y"; else _default="N"; fi
    fi
    if confirm "  Enable ${SERVICE_DESC[$name]}?" "${_default}"; then
        PROFILES+=("$name")
    fi
done

# At most one display app, since they'd fight over the HDMI output. Defaults
# to whichever is enabled now.
echo
echo "  HDMI display app, for a TV/projector plugged into the server (pick one):"
echo "    1) None"
_display_default=1
for i in "${!DISPLAY_APPS[@]}"; do
    echo "    $((i + 2))) ${SERVICE_DESC[${DISPLAY_APPS[$i]}]}"
    if [ "${_display_default}" = 1 ] && profile_enabled "${DISPLAY_APPS[$i]}"; then
        _display_default=$((i + 2))
    fi
done
pick _display_choice $(( ${#DISPLAY_APPS[@]} + 1 )) "${_display_default}" "  Choice"
if [ "${_display_choice}" -gt 1 ]; then
    PROFILES+=("${DISPLAY_APPS[$((_display_choice - 2))]}")
fi

# Add the DNS provider profile so the right DDNS container starts.
[ "${DNS_PROVIDER}" != "none" ] && PROFILES+=("${DNS_PROVIDER}")

if [ ${#PROFILES[@]} -eq 0 ]; then
    COMPOSE_PROFILES=""
    echo "  Warning: no services selected. Only infrastructure will start."
else
    COMPOSE_PROFILES="$(IFS=,; echo "${PROFILES[*]}")"
fi

# --- Service settings -------------------------------------------------------
run_hooks prompt

# --- Write .env -------------------------------------------------------------
write_env "${ENV_FILE}"
run_hooks post_setup

# --- Remove the display apps that aren't enabled ----------------------------
# Disabling a profile leaves its containers behind, and display apps would
# fight over the display.
if command -v docker >/dev/null 2>&1; then
    _stale=()
    for name in "${DISPLAY_APPS[@]}"; do
        profile_enabled "$name" && continue
        for _c in $("${name}_containers"); do
            docker inspect "$_c" >/dev/null 2>&1 && _stale+=("$_c")
        done
    done
    if [ ${#_stale[@]} -gt 0 ]; then
        echo
        if confirm "Remove the containers of the display apps you didn't pick (${_stale[*]})?" Y; then
            docker rm -f "${_stale[@]}" >/dev/null && echo "  Removed: ${_stale[*]}"
        else
            echo "  Kept. They'll fight over the display if both run - remove them with: docker rm -f ${_stale[*]}"
        fi
    fi
fi

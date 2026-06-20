#!/bin/bash
# env-generate.sh
# Non-interactive .env generator — the scripted counterpart to env-setup.sh.
#
# All inputs are read from environment variables so secrets never appear in
# the process list. Call this from Ansible, CI, or any non-interactive context.
#
# Required vars:
#   CERTBOT_EMAIL     email for Let's Encrypt notifications
#   NOIP_NAME         DDNS hostname prefix (the part before .ddns.net)
#   NOIP_USERNAME     DDNS Key username
#   NOIP_PASSWORD     DDNS Key password
#   COMPOSE_PROFILES  comma-separated list of enabled service profiles
#                     (empty = only infrastructure; a warning is printed)
#
# Optional vars (auto-detected or defaulted when absent/empty):
#   LOCAL_IP                      server LAN IP; auto-detected if empty
#   DNS1                          upstream DNS 1  (default: 1.1.1.1)
#   DNS2                          upstream DNS 2  (default: 8.8.8.8)
#   PLEX_CLAIM                    claim token from plex.tv/claim (default: empty)
#   PLEX_HTTPS_PORT               nginx TLS port for Plex (default: 8443)
#   FILEBROWSER_ROOT              filebrowser root path (default: /srv/mergerfs/media/share)
#   INITIAL_FILEBROWSER_PASSWORD  initial filebrowser admin password (default: hellofilebrowser)
#
# Exit codes:
#   0  .env written successfully
#   1  validation error (message printed to stderr)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/.env"

# shellcheck source=env-lib.sh
source "${SCRIPT_DIR}/env-lib.sh"

fail() { echo "Error: $*" >&2; exit 1; }

# --- Required inputs ---------------------------------------------------------
CERTBOT_EMAIL="${CERTBOT_EMAIL:-}"
NOIP_NAME="${NOIP_NAME:-}"
NOIP_USERNAME="${NOIP_USERNAME:-}"
NOIP_PASSWORD="${NOIP_PASSWORD:-}"
COMPOSE_PROFILES="${COMPOSE_PROFILES:-}"

[ -n "$CERTBOT_EMAIL" ]  || fail "CERTBOT_EMAIL is required."
[ -n "$NOIP_NAME" ]      || fail "NOIP_NAME is required."
[ -n "$NOIP_USERNAME" ]  || fail "NOIP_USERNAME is required."
[ -n "$NOIP_PASSWORD" ]  || fail "NOIP_PASSWORD is required."

[ -n "$COMPOSE_PROFILES" ] \
    || echo "Warning: COMPOSE_PROFILES is empty; only infrastructure containers will start." >&2

# --- LOCAL_IP: auto-detect if not supplied -----------------------------------
LOCAL_IP="${LOCAL_IP:-}"
if [ -z "$LOCAL_IP" ]; then
    LOCAL_IP="$(detect_local_ip)"
    [ -n "$LOCAL_IP" ] \
        || fail "Could not auto-detect LOCAL_IP. Set it explicitly via the LOCAL_IP env var."
    echo "Auto-detected LOCAL_IP: ${LOCAL_IP}" >&2
else
    validate_ipv4 "$LOCAL_IP" \
        || fail "LOCAL_IP '${LOCAL_IP}' is not a valid IPv4 address."
    if ! is_private_ipv4 "$LOCAL_IP"; then
        echo "Warning: LOCAL_IP '${LOCAL_IP}' is not in a private RFC-1918 range." >&2
    fi
fi

# --- Optional inputs with defaults -------------------------------------------
DNS1="${DNS1:-1.1.1.1}"
DNS2="${DNS2:-8.8.8.8}"
NOIP_HOSTNAMES="all.ddnskey.com"
PLEX_CLAIM="${PLEX_CLAIM:-}"
PLEX_HTTPS_PORT="${PLEX_HTTPS_PORT:-8443}"
FILEBROWSER_ROOT="${FILEBROWSER_ROOT:-/srv/mergerfs/media/share}"
INITIAL_FILEBROWSER_PASSWORD="${INITIAL_FILEBROWSER_PASSWORD:-hellofilebrowser}"

[[ "$PLEX_HTTPS_PORT" =~ ^[0-9]+$ ]] && (( PLEX_HTTPS_PORT >= 1 && PLEX_HTTPS_PORT <= 65535 )) \
    || fail "PLEX_HTTPS_PORT '${PLEX_HTTPS_PORT}' must be a number between 1 and 65535."

# --- Write .env --------------------------------------------------------------
write_env "${ENV_FILE}"

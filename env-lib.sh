#!/bin/bash
# env-lib.sh
# Shared helpers sourced by env-setup.sh and env-generate.sh.
# Do not execute directly.

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Optional services, in the order env-setup.sh asks about them. Each has a
# <name>/env.sh module (see "Service modules" below).
SERVICES=(jellyfin plex universalmediaserver navidrome audiobookshelf stash filebrowser fileflows tv kodi)

fail() { echo "Error: $*" >&2; exit 1; }

validate_ipv4() {
    [[ $1 =~ ^([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})$ ]] || return 1
    local a=${BASH_REMATCH[1]} b=${BASH_REMATCH[2]} c=${BASH_REMATCH[3]} d=${BASH_REMATCH[4]}
    (( a <= 255 && b <= 255 && c <= 255 && d <= 255 ))
}

is_private_ipv4() {
    validate_ipv4 "$1" || return 1
    [[ $1 =~ ^([0-9]+)\.([0-9]+)\. ]]
    local a=${BASH_REMATCH[1]} b=${BASH_REMATCH[2]}
    (( a == 10 )) && return 0
    (( a == 172 && b >= 16 && b <= 31 )) && return 0
    (( a == 192 && b == 168 )) && return 0
    return 1
}

valid_port() {
    [[ $1 =~ ^[0-9]+$ ]] && (( $1 >= 1 && $1 <= 65535 ))
}

# Detects the server's LAN IP via kernel routing table.
# Prints the detected IP on stdout, or nothing on failure.
detect_local_ip() {
    ip -4 route get 1.1.1.1 2>/dev/null \
        | awk '{for(i=1;i<=NF;i++) if($i=="src") print $(i+1)}' || true
}

# Detects the network interface used to reach the internet, via the kernel
# routing table. Prints the detected interface name on stdout, or nothing
# on failure.
detect_local_interface() {
    ip -4 route get 1.1.1.1 2>/dev/null \
        | awk '{for(i=1;i<=NF;i++) if($i=="dev") print $(i+1)}' || true
}

# Checks whether a network interface exists on this host.
interface_exists() {
    [ -n "$1" ] && [ -d "/sys/class/net/$1" ]
}

# Checks whether profile $1 is in COMPOSE_PROFILES.
profile_enabled() {
    [[ ",${COMPOSE_PROFILES}," == *",$1,"* ]]
}

# --- Prompts -----------------------------------------------------------------

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

# Like ask, but repeats until the value isn't empty.
ask_required() {
    ask "$1" "$2"
    while [ -z "${!1}" ]; do
        read -r -p "  This can't be empty. Try again: " "$1"
    done
}

# Asks a yes/no question. Returns 0 for yes.
# Usage: confirm "Question?" DEFAULT   (DEFAULT is Y or N)
confirm() {
    local _hint="[y/N]" _ans
    [ "$2" = "Y" ] && _hint="[Y/n]"
    read -r -p "$1 ${_hint} " _ans
    [[ "${_ans:-$2}" =~ ^[yY]([eE][sS])?$ ]]
}

# Reads a menu choice from 1 to COUNT.
# Usage: pick VARNAME COUNT DEFAULT ["Prompt text"]
pick() {
    local _ans
    read -r -p "${4:-Select} [${3}]: " _ans
    _ans="${_ans:-$3}"
    while ! [[ "$_ans" =~ ^[0-9]+$ ]] || (( _ans < 1 || _ans > $2 )); do
        read -r -p "  Please enter a number from 1 to $2: " _ans
    done
    printf -v "$1" '%s' "$_ans"
}

# --- Service modules ---------------------------------------------------------
# Each <name>/env.sh calls register_service, and can define these hooks as
# functions named <name>_<hook>:
#   defaults    set defaults with ${VAR:=value}, keeping values already set
#   prompt      ask the service's questions (env-setup.sh)
#   validate    check or fill in values, using fail on bad input (env-generate.sh)
#   env         print the service's .env section
#   summary     print lines for the summary shown after .env is written
#   post_setup  run steps that need the new .env (env-setup.sh)
#   containers  print the service's container names (display services only)
# defaults and env run for every service, so settings survive a service being
# turned off. The others only run for enabled services.

declare -A SERVICE_DESC=() SERVICE_DEFAULT=() SERVICE_GROUP=()

# Usage: register_service NAME "Description" DEFAULT [GROUP]
# DEFAULT (Y or N) is the answer env-setup.sh suggests on a fresh install.
# GROUP "display" marks apps that drive the HDMI output; at most one of those
# is enabled.
register_service() {
    SERVICE_DESC[$1]="$2"
    SERVICE_DEFAULT[$1]="$3"
    SERVICE_GROUP[$1]="${4:-}"
}

# Runs hook $1 of every enabled service that defines it, or of every service
# when $2 is "all".
run_hooks() {
    local name
    for name in "${SERVICES[@]}"; do
        if declare -F "${name}_$1" >/dev/null \
            && { [ "${2:-}" = "all" ] || profile_enabled "$name"; }; then
            "${name}_$1"
        fi
    done
}

for _service in "${SERVICES[@]}"; do
    # shellcheck source=/dev/null
    source "${REPO_DIR}/${_service}/env.sh"
done
unset _service

# --- .env --------------------------------------------------------------------

# Writes .env and prints a summary to stderr. The core settings (see the top
# of env-setup.sh) and every service's defaults must be set before calling.
# $1 = destination file path
write_env() {
    local env_file="$1" name
    umask 077

    {
        cat <<EOF
# Generated on $(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Let's Encrypt / Certbot
CERTBOT_EMAIL=${CERTBOT_EMAIL}
# Set STAGING=1 to test before requesting a real certificate.
# Remove or set to empty once you have confirmed cert issuance works.
STAGING=

# DNS provider: none | noip | cloudflare
DNS_PROVIDER=${DNS_PROVIDER}

# Public domain / FQDN used across all services and TLS certificates.
DOMAIN=${DOMAIN}

EOF

        case "${DNS_PROVIDER}" in
            noip)
                cat <<EOF
# No-IP DDNS credentials
NOIP_USERNAME=${NOIP_USERNAME}
NOIP_PASSWORD=${NOIP_PASSWORD}
NOIP_HOSTNAMES=${NOIP_HOSTNAMES}

EOF
                ;;
            cloudflare)
                cat <<EOF
# Cloudflare API token with DNS edit permission for ${DOMAIN}
CF_API_TOKEN=${CF_API_TOKEN}

EOF
                ;;
        esac

        cat <<EOF
# Server LAN IP
LOCAL_IP=${LOCAL_IP}

# Upstream DNS servers
# Safe to edit; restart the dnsmasq container after changing.
DNS1=${DNS1}
DNS2=${DNS2}

EOF

        case "${INTERNAL_DNS_ADAPTER:-}" in
            opnsense)
                cat <<EOF
# Internal DNS sync: internal-dns-init pushes a ${DOMAIN} -> ${LOCAL_IP} host
# override to the router's resolver on each 'up' (scripts/sync-internal-dns.py).
INTERNAL_DNS_ADAPTER=${INTERNAL_DNS_ADAPTER}
OPNSENSE_URL=${OPNSENSE_URL}
OPNSENSE_API_KEY=${OPNSENSE_API_KEY}
OPNSENSE_API_SECRET=${OPNSENSE_API_SECRET}
OPNSENSE_TLS_VERIFY=${OPNSENSE_TLS_VERIFY}

EOF
                ;;
        esac

        cat <<EOF
# Media pool (the mergerfs mount) holding movies/, tv/, music/, audiobooks/,
# podcasts/, vr/ and extra/. Mounted into the media services.
MEDIA_ROOT=${MEDIA_ROOT}

# Which services to run (Docker Compose profiles). Comma-separated, no spaces.
# Includes media service profiles (jellyfin, plex, ...) and the DNS provider
# profile (noip or cloudflare). Edit and re-run 'docker compose up -d' to change.
COMPOSE_PROFILES=${COMPOSE_PROFILES}
EOF

        for name in "${SERVICES[@]}"; do
            if declare -F "${name}_env" >/dev/null; then
                echo
                "${name}_env"
            fi
        done
    } > "${env_file}"

    chmod 600 "${env_file}"
    {
        echo "Wrote ${env_file} (mode 600)."
        echo
        echo "Public URL:       https://${DOMAIN}"
        echo "LAN IP:           ${LOCAL_IP}"
        echo "DNS provider:     ${DNS_PROVIDER}"
        if [ -n "${INTERNAL_DNS_ADAPTER:-}" ]; then
            echo "Router DNS sync:  ${INTERNAL_DNS_ADAPTER}"
        fi
        echo "Enabled services: ${COMPOSE_PROFILES:-<none>}"
        echo "Status (LAN):     http://${LOCAL_IP}:8090"
        run_hooks summary
    } >&2
}

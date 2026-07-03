#!/bin/bash
# env-lib.sh
# Shared helpers sourced by env-setup.sh and env-generate.sh.
# Do not execute directly.

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

# Writes .env and prints a summary to stderr.
# DNS_PROVIDER, DOMAIN, CERTBOT_EMAIL, LOCAL_IP, DNS1, DNS2,
# COMPOSE_PROFILES, PLEX_CLAIM, PLEX_HTTPS_PORT,
# FILEBROWSER_ROOT, INITIAL_FILEBROWSER_PASSWORD, UMS_NETWORK_INTERFACE
# must be set before calling.
# Provider-specific vars (NOIP_* or CF_API_TOKEN) must also be set when relevant,
# as must OPNSENSE_* when INTERNAL_DNS_ADAPTER=opnsense.
# $1 = destination file path
write_env() {
    local env_file="$1"
    umask 077

    cat > "${env_file}" <<EOF
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
            cat >> "${env_file}" <<EOF
# No-IP DDNS credentials
NOIP_USERNAME=${NOIP_USERNAME}
NOIP_PASSWORD=${NOIP_PASSWORD}
NOIP_HOSTNAMES=${NOIP_HOSTNAMES}

EOF
            ;;
        cloudflare)
            cat >> "${env_file}" <<EOF
# Cloudflare API token with DNS edit permission for ${DOMAIN}
CF_API_TOKEN=${CF_API_TOKEN}

EOF
            ;;
    esac

    cat >> "${env_file}" <<EOF
# Server LAN IP
LOCAL_IP=${LOCAL_IP}

# Upstream DNS servers
# Safe to edit; restart the dnsmasq container after changing.
DNS1=${DNS1}
DNS2=${DNS2}

EOF

    case "${INTERNAL_DNS_ADAPTER:-}" in
        opnsense)
            cat >> "${env_file}" <<EOF
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

    cat >> "${env_file}" <<EOF
# The root directory for the filebrowser web UI
FILEBROWSER_ROOT=${FILEBROWSER_ROOT}
# Initial password for Filebrowser admin
INITIAL_FILEBROWSER_PASSWORD=${INITIAL_FILEBROWSER_PASSWORD}

# Which services to run (Docker Compose profiles). Comma-separated, no spaces.
# Includes media service profiles (jellyfin, plex, ...) and the DNS provider
# profile (noip or cloudflare). Edit and re-run 'docker compose up -d' to change.
COMPOSE_PROFILES=${COMPOSE_PROFILES}

# Universal Media Server
# Host LAN network interface (e.g. eth0, enp2s0) UMS's DLNA/UPnP discovery
# binds to. Required so SSDP multicast discovery reaches real LAN/Wi-Fi clients. 
# Only applied on a fresh UMS profile dir; see UniversalMediaServerSetupGuide.md.
UMS_NETWORK_INTERFACE=${UMS_NETWORK_INTERFACE}

# Plex
# One-time claim token from https://www.plex.tv/claim (only for first setup).
PLEX_CLAIM=${PLEX_CLAIM}
# Port nginx uses to serve Plex over HTTPS (Plex can't live under a subpath).
PLEX_HTTPS_PORT=${PLEX_HTTPS_PORT}
EOF

    chmod 600 "${env_file}"
    echo "Wrote ${env_file} (mode 600)." >&2
    echo >&2
    echo "Public URL:       https://${DOMAIN}" >&2
    echo "LAN IP:           ${LOCAL_IP}" >&2
    echo "DNS provider:     ${DNS_PROVIDER}" >&2
    if [ -n "${INTERNAL_DNS_ADAPTER:-}" ]; then
        echo "Router DNS sync:  ${INTERNAL_DNS_ADAPTER}" >&2
    fi
    echo "Enabled services: ${COMPOSE_PROFILES:-<none>}" >&2
    case ",${COMPOSE_PROFILES}," in
        *,plex,*) echo "Plex URL:         https://${DOMAIN}:${PLEX_HTTPS_PORT}/web" >&2 ;;
    esac
    case ",${COMPOSE_PROFILES}," in
        *,universalmediaserver,*) echo "UMS admin (LAN):  http://${LOCAL_IP}:9001" >&2 ;;
    esac
}

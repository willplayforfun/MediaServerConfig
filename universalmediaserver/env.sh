# env-setup.sh module (see "Service modules" in env-lib.sh).
register_service universalmediaserver "Universal Media Server (DLNA, UPnP)" N

universalmediaserver_defaults() {
    : "${UMS_NETWORK_INTERFACE:=}"
}

universalmediaserver_prompt() {
    echo
    echo "Universal Media Server is enabled."
    echo "  Its DLNA/UPnP discovery must bind to the host's real LAN interface."
    : "${UMS_NETWORK_INTERFACE:=$(detect_local_interface)}"
    ask UMS_NETWORK_INTERFACE "  LAN network interface name"
    while ! interface_exists "${UMS_NETWORK_INTERFACE}"; do
        read -r -p "  '${UMS_NETWORK_INTERFACE}' was not found on this host (see 'ip addr'). Try again: " UMS_NETWORK_INTERFACE
    done
}

universalmediaserver_validate() {
    if [ -z "${UMS_NETWORK_INTERFACE}" ]; then
        UMS_NETWORK_INTERFACE="$(detect_local_interface)"
        [ -n "${UMS_NETWORK_INTERFACE}" ] \
            || fail "Could not auto-detect UMS_NETWORK_INTERFACE. Set it explicitly via the UMS_NETWORK_INTERFACE env var."
        echo "Auto-detected UMS_NETWORK_INTERFACE: ${UMS_NETWORK_INTERFACE}" >&2
    else
        interface_exists "${UMS_NETWORK_INTERFACE}" \
            || fail "UMS_NETWORK_INTERFACE '${UMS_NETWORK_INTERFACE}' was not found on this host."
    fi
}

universalmediaserver_env() {
    cat <<EOF
# Universal Media Server
# Host LAN network interface (e.g. eth0, enp2s0) UMS's DLNA/UPnP discovery
# binds to. Required so SSDP multicast discovery reaches real LAN/Wi-Fi clients.
# Only applied on a fresh UMS profile dir; see docs/UniversalMediaServerSetupGuide.md.
UMS_NETWORK_INTERFACE=${UMS_NETWORK_INTERFACE}
EOF
}

universalmediaserver_summary() {
    echo "UMS admin (LAN):  http://${LOCAL_IP}:9001"
}

# env-setup.sh module (see "Service modules" in env-lib.sh).
register_service plex "Plex (video streaming)" N

# nginx publishes PLEX_HTTPS_PORT even when Plex is off, so it always needs a value.
plex_defaults() {
    : "${PLEX_CLAIM:=}"
    : "${PLEX_HTTPS_PORT:=8443}"
}

plex_prompt() {
    echo
    echo "Plex is enabled."
    echo "  Get a claim token from https://www.plex.tv/claim (valid ~4 minutes)."
    ask PLEX_CLAIM "  Plex claim token"
    ask PLEX_HTTPS_PORT "  HTTPS port"
    while ! valid_port "${PLEX_HTTPS_PORT}"; do
        read -r -p "  Enter a port number from 1 to 65535: " PLEX_HTTPS_PORT
    done
    echo "  Remember to forward external port ${PLEX_HTTPS_PORT} for remote access."
}

plex_validate() {
    valid_port "${PLEX_HTTPS_PORT}" \
        || fail "PLEX_HTTPS_PORT '${PLEX_HTTPS_PORT}' must be a number between 1 and 65535."
}

plex_env() {
    cat <<EOF
# Plex
# One-time claim token from https://www.plex.tv/claim (only for first setup).
PLEX_CLAIM=${PLEX_CLAIM}
# Port nginx uses to serve Plex over HTTPS (Plex can't live under a subpath).
PLEX_HTTPS_PORT=${PLEX_HTTPS_PORT}
EOF
}

plex_summary() {
    echo "Plex URL:         https://${DOMAIN}:${PLEX_HTTPS_PORT}/web"
}

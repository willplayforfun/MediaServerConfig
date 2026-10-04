# env-setup.sh module (see "Service modules" in env-lib.sh).
register_service filebrowser "Filebrowser (web file manager)" Y

filebrowser_defaults() {
    : "${FILEBROWSER_ROOT:=${MEDIA_ROOT}/share}"
    : "${INITIAL_FILEBROWSER_PASSWORD:=hellofilebrowser}"
}

filebrowser_env() {
    cat <<EOF
# The root directory for the filebrowser web UI
FILEBROWSER_ROOT=${FILEBROWSER_ROOT}
# Initial password for Filebrowser admin
INITIAL_FILEBROWSER_PASSWORD=${INITIAL_FILEBROWSER_PASSWORD}
EOF
}

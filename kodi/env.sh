# env-setup.sh module (see "Service modules" in env-lib.sh).
register_service kodi "Kodi (media center)" N display

kodi_containers() {
    echo kodi
}

kodi_summary() {
    echo "Kodi web UI (LAN): http://${LOCAL_IP}:8080"
}

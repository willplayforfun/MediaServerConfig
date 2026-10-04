# env-setup.sh module (see "Service modules" in env-lib.sh).
register_service tv "TV launcher (smart-TV home screen with app tiles, sleeps when idle)" N display

tv_defaults() {
    : "${REMOTE_DEVICES:=}"
    : "${HOME_KEY:=KEY_HOMEPAGE}"
    : "${SLEEP_KEY:=}"
    : "${TV_AUDIO_DEVICE:=hdmi:CARD=PCH,DEV=0}"
}

tv_prompt() {
    local -a candidates picked
    local sel n i ok
    echo
    echo "TV launcher is enabled. The hub reads the remote directly: its Home"
    echo "button returns to the launcher (hold it to turn the display off), and"
    echo "any button wakes the display. If you don't know the remote's device"
    echo "or its Home button's key name yet, run 'sudo evtest' in another"
    echo "terminal first."
    echo

    shopt -s nullglob
    candidates=(/dev/input/by-id/*-event-*)
    shopt -u nullglob

    if [ ${#candidates[@]} -eq 0 ]; then
        echo "  No devices found under /dev/input/by-id/ - the hub will watch every"
        echo "  input device. Re-run this once the remote is plugged in to narrow it."
    else
        echo "  Available input devices:"
        for i in "${!candidates[@]}"; do
            printf "    %d) %s\n" "$((i + 1))" "${candidates[$i]}"
        done
        echo "  Current: ${REMOTE_DEVICES:-all devices}"
        while true; do
            read -r -p "  Remote's device numbers, space-separated (Enter = keep current, 'all' = every device): " sel
            case "$sel" in
                "") break ;;
                all) REMOTE_DEVICES=""; break ;;
            esac
            picked=()
            ok=true
            for n in $sel; do
                if [[ "$n" =~ ^[0-9]+$ ]] && [ "$n" -ge 1 ] && [ "$n" -le ${#candidates[@]} ]; then
                    picked+=("${candidates[$((n - 1))]}")
                else
                    echo "  '$n' isn't one of the listed numbers."
                    ok=false
                fi
            done
            if $ok; then
                REMOTE_DEVICES="$(IFS=,; echo "${picked[*]}")"
                break
            fi
        done
    fi

    ask_required HOME_KEY "  Key name evtest reported for the remote's Home button (or its numeric code)"
    ask SLEEP_KEY "  Optional button that turns the display off straight away (Enter to skip)"
    if command -v aplay >/dev/null 2>&1; then
        echo "  HDMI audio devices on this host (with the TV apps stopped, test one with"
        echo "  'speaker-test -D <device> -c 2 -t sine -l 1'):"
        aplay -L 2>/dev/null | grep '^hdmi:' | sed 's/^/    /' || echo "    (none found)"
    fi
    ask TV_AUDIO_DEVICE "  ALSA device for HDMI audio"
}

tv_env() {
    cat <<EOF
# TV launcher (tv profile only)
# Remote: comma-separated /dev/input/by-id/ paths, blank = every device
REMOTE_DEVICES=${REMOTE_DEVICES}
# evdev key names or numeric codes
HOME_KEY=${HOME_KEY}
SLEEP_KEY=${SLEEP_KEY}
# ALSA device the TV apps play sound on
TV_AUDIO_DEVICE=${TV_AUDIO_DEVICE}
EOF
}

tv_summary() {
    echo "TV remote:        ${REMOTE_DEVICES:-all input devices} (Home: ${HOME_KEY}${SLEEP_KEY:+, sleep: ${SLEEP_KEY}})"
    echo "TV audio:         ${TV_AUDIO_DEVICE}"
}

# `compose up` never starts the "tv-apps" profile, so the hub needs them
# created once.
tv_post_setup() {
    echo
    if ! confirm "Create the tv-apps containers now (required before the launcher can show anything)?" Y; then
        echo "  Skipped. Run 'docker compose --profile tv-apps create' before using the launcher."
    elif ! command -v docker >/dev/null 2>&1; then
        echo "  Warning: docker not found on PATH. Run this manually later:" >&2
        echo "    docker compose --profile tv-apps create" >&2
    elif ( cd "${REPO_DIR}" && docker compose --profile tv-apps create ); then
        echo "  tv-apps containers created."
    else
        echo "  Warning: container creation failed. Run this manually once it's fixed:" >&2
        echo "    docker compose --profile tv-apps create" >&2
    fi
}

tv_containers() {
    echo tv-hub tv-home tv-youtube
}

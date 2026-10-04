#!/bin/sh
# Copies each enabled profile's <profile>/SRC (or SRC.tmpl, via envsubst with $VARS) to DEST/<profile>.<ext>.
# Usage: collect-profile-files.sh SRC DEST   (env: REPO, COMPOSE_PROFILES)
set -eu

: "${REPO:?REPO not set}"
src=${1:?usage: collect-profile-files.sh SRC DEST}
dest=${2:?usage: collect-profile-files.sh SRC DEST}
ext=${src##*.}

mkdir -p "$dest"
for profile in $(echo "${COMPOSE_PROFILES:-}" | tr ',' ' '); do
    if [ -f "$REPO/$profile/$src" ]; then
        cp "$REPO/$profile/$src" "$dest/$profile.$ext"
    elif [ -f "$REPO/$profile/$src.tmpl" ]; then
        envsubst "${VARS:?VARS not set}" < "$REPO/$profile/$src.tmpl" > "$dest/$profile.$ext"
    else
        continue
    fi
    echo "$profile: $src"
done

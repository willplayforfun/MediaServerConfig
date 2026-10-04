#!/bin/sh
# Builds Gatus's config dir: gatus/config.yaml plus <profile>/gatus.yaml for
# each profile in COMPOSE_PROFILES. Run by the gatus-render container on `up`.
set -eu

: "${REPO:?REPO not set}"
: "${OUT:?OUT not set}"

mkdir -p "$OUT"
# Rewrite every file, not just the changes: Gatus reloads only when a file's
# mtime moves, so a disabled profile's file vanishing alone wouldn't trigger it.
rm -f "$OUT"/*.yaml
cp "$REPO/gatus/config.yaml" "$OUT/00-core.yaml"
/bin/sh "$(dirname "$0")/collect-profile-files.sh" gatus.yaml "$OUT"

chmod -R a+rX "$OUT"

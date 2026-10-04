#!/bin/sh
# Builds nginx's conf.d from nginx-configs/ plus each enabled profile's nginx-*.conf.
# Run by the nginx-render container on `up`.
set -eu

: "${REPO:?REPO not set}"
: "${OUT:?OUT not set}"
collect="$(dirname "$0")/collect-profile-files.sh"

mkdir -p "$OUT"
rm -rf "${OUT:?}"/*   # a disabled service's files must not linger
cp -r "$REPO/nginx-configs/." "$OUT/"
/bin/sh "$collect" nginx-server.conf "$OUT"
/bin/sh "$collect" nginx-locations.conf "$OUT/locations"

chmod -R a+rX "$OUT"

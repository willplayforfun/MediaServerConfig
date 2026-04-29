#!/bin/sh
# render-templates.sh
# Generic template renderer. Walks $IN, copies every file into $OUT.
# Files ending in .tmpl are rendered through envsubst (restricted to the
# placeholders listed in $VARS) and have their .tmpl suffix dropped.
# Non-template files are copied verbatim, preserving directory structure.
#
# Required environment:
#   IN     source directory (read-only is fine)
#   OUT    output directory (created if missing)
#   VARS   space-separated envsubst allowlist, e.g. '${NOIP_NAME} ${LOCAL_IP}'
#
# Every variable named in VARS must also be present in the environment.
# Designed to run inside the renderer image built from
# scripts/render-templates.Dockerfile, where envsubst is pre-installed.
# Can also be run on any host that has gettext installed.
#
# To swap envsubst for a more capable engine (gomplate, jinja, mustache, ...),
# replace the rendering line below and update the Dockerfile to match.
set -eu

: "${IN:?IN not set}"
: "${OUT:?OUT not set}"
: "${VARS:?VARS not set}"

if ! command -v envsubst >/dev/null 2>&1; then
    echo "render-templates.sh: envsubst not found." >&2
    echo "  Run inside the renderer image, or install the gettext package." >&2
    exit 1
fi

mkdir -p "$OUT"

# Walk every regular file under IN. We control the inputs, so this stays simple.
( cd "$IN" && find . -type f ) | while IFS= read -r rel; do
    rel=${rel#./}
    src="$IN/$rel"

    case "$rel" in
        *.tmpl)
            dst="$OUT/${rel%.tmpl}"
            mkdir -p "$(dirname "$dst")"
            envsubst "$VARS" < "$src" > "$dst"
            echo "rendered $rel -> ${rel%.tmpl}"
            ;;
        *)
            dst="$OUT/$rel"
            mkdir -p "$(dirname "$dst")"
            cp "$src" "$dst"
            echo "copied   $rel"
            ;;
    esac
done

# Make rendered output readable by non-root services (e.g. nginx).
chmod -R a+rX "$OUT"

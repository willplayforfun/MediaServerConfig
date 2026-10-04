#!/bin/sh
# render-templates.sh
# Copies every file in $IN to $OUT. *.tmpl files go through envsubst and lose
# the suffix; only placeholders listed in $VARS are replaced, so other $words
# (e.g. nginx variables) pass through.
#
# Env: IN (source dir), OUT (output dir), VARS (allowlist, e.g.
# '${DOMAIN} ${LOCAL_IP}'). Each variable in VARS must also be set.
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

#!/bin/sh
# cert-init.sh
#
# One-shot certificate issuance. Run as a Docker service before nginx starts.
#
# - If the certificate already exists, exits immediately (fast path on restarts).
# - If not, uses certbot standalone mode to obtain a new certificate.
#   Standalone binds port 80 directly; nginx hasn't started yet so the port is free.
#
# The cert is always named 'homeserver' (--cert-name) so the path is fixed
# regardless of which domain is used, and nginx.conf needs no templating.
#
# Required environment variables:
#   DOMAIN  – the public FQDN, e.g. myserver.ddns.net
#   EMAIL   – contact address for Let's Encrypt expiry notifications
#
# Optional:
#   STAGING – set to any non-empty value to use Let's Encrypt staging CA.
#             You can do a staging run to verify port forwarding is correct.

CERT_PATH="/etc/letsencrypt/live/homeserver/fullchain.pem"

if [ -f "$CERT_PATH" ]; then
    echo "[cert-init] Certificate already exists at $CERT_PATH. Nothing to do."
    exit 0
fi

if [ -z "$DOMAIN" ]; then
    echo "[cert-init] ERROR: DOMAIN environment variable is not set." >&2
    exit 0
fi

if [ -z "$EMAIL" ]; then
    echo "[cert-init] ERROR: EMAIL environment variable is not set." >&2
    exit 0
fi

STAGING_FLAG=""
if [ -n "${STAGING:-}" ]; then
    echo "[cert-init] STAGING mode — certificate will not be trusted by browsers."
    STAGING_FLAG="--staging"
fi

echo "[cert-init] Waiting for DNS to resolve $DOMAIN ..."
MAX_WAIT=300
ELAPSED=0
until nslookup "$DOMAIN" > /dev/null 2>&1; do
    if [ "$ELAPSED" -ge "$MAX_WAIT" ]; then
        echo "[cert-init] ERROR: DNS did not resolve for $DOMAIN after ${MAX_WAIT}s. Check your DDNS/DNS configuration." >&2
        exit 0
    fi
    echo "[cert-init] Not yet resolved, retrying in 10s... (${ELAPSED}s elapsed)"
    sleep 10
    ELAPSED=$((ELAPSED + 10))
done
echo "[cert-init] DNS resolved. Requesting certificate for $DOMAIN ..."

certbot certonly \
    --standalone \
    --cert-name homeserver \
    -d "$DOMAIN" \
    --email "$EMAIL" \
    --agree-tos \
    --no-eff-email \
    --non-interactive \
    $STAGING_FLAG

echo "[cert-init] Certificate issued successfully."

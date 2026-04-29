#!/bin/sh
# certbot-renew.sh
#
# Long-running renewal loop. Run as a Docker service alongside nginx.
#
# Sleeps 12 hours between renewal checks. Certbot only actually renews when
# the certificate is within 30 days of expiry, so this is safe to run
# frequently. On renewal, a deploy hook reloads nginx so it picks up the
# new certificate without downtime.
#
# Requires the Docker socket to be mounted so it can exec into the nginx
# container for the reload:
#   volumes:
#     - /var/run/docker.sock:/var/run/docker.sock
#
# Uses webroot mode: nginx must be running and serving
# /.well-known/acme-challenge/ from /var/www/certbot (shared volume).

set -e

echo "[certbot-renew] Installing docker-cli for nginx reload hook..."
apk add --no-cache docker-cli > /dev/null 2>&1
echo "[certbot-renew] Ready. Renewal loop starting (12h interval)."

while true; do
    # Sleep first — cert-init just ran, no point checking immediately.
    sleep 12h & wait $!

    echo "[certbot-renew] Checking for certificate renewal..."
    certbot renew \
        --webroot -w /var/www/certbot \
        --deploy-hook "docker exec nginx nginx -s reload"

    echo "[certbot-renew] Renewal check complete."
done

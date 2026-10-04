# Image for the *-render services (homeserver-renderer:local). envsubst is
# baked in so they don't install a package on every `up`.
FROM alpine:3.20

RUN apk add --no-cache gettext

COPY render-templates.sh /render.sh
RUN chmod +x /render.sh

ENTRYPOINT ["/bin/sh", "/render.sh"]

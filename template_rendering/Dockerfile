# Renderer image used by helpsite-render and dnsmasq-render in docker-compose.yml.
# Tiny Alpine layer with envsubst (gettext) and render-templates.sh baked in,
# so the renderer containers don't have to install a package on every `up`.
#
# Build context is ./scripts so the COPY below stays cheap; see scripts/.dockerignore.
# To swap envsubst for a more capable engine (gomplate, jinja, ...), change the
# package install and the entrypoint here, plus the rendering line in the script.
FROM alpine:3.20

RUN apk add --no-cache gettext

COPY render-templates.sh /render.sh
RUN chmod +x /render.sh

ENTRYPOINT ["/bin/sh", "/render.sh"]

#!/bin/sh
# Backgrounds the remote-button watcher, then execs cog as the foreground
# process. The container runs with init: true (tini as PID 1), so tini
# reaps both this and the backgrounded watcher correctly, and `docker stop`
# tears the whole thing down cleanly.
set -e

python3 /watcher.py &

exec cog --platform=drm "${YOUTUBE_TV_URL:-https://www.youtube.com/tv}"

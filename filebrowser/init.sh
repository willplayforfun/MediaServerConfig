#!/bin/sh
set -e

DB=/database/filebrowser.db

# On first run, seed the database with a known admin account.
# Subsequent starts skip this block entirely.
if [ ! -s "$DB" ]; then
    filebrowser config init --database "$DB"
    filebrowser users add admin "${INITIAL_FILEBROWSER_PASSWORD}" \
        --database "$DB" \
        --perm.admin=true
fi

exec filebrowser --config /config/settings.json

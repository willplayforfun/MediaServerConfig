#!/bin/bash
# Clear an Audiobookshelf user's password by setting pash to NULL.
# Runs sqlite3 via a temporary Docker container so the host needs no extra tools.
# Usage: ./abs-reset-user.sh <username>
# Run from: /opt/docker/

set -euo pipefail

CONTAINER_NAME="${ABS_CONTAINER:-audiobookshelf}"
SQLITE_IMAGE="${SQLITE_IMAGE:-keinos/sqlite3:latest}"

# --- Helpers -----------------------------------------------------------------

usage() {
    echo "Usage: $0 <username>"
    echo ""
    echo "Clears an Audiobookshelf user's password (sets pash to NULL)."
    echo ""
    echo "Environment variables:"
    echo "  ABS_CONTAINER   Docker container name/ID (default: audiobookshelf)"
    echo "  SQLITE_IMAGE    sqlite3 Docker image to use (default: keinos/sqlite3:latest)"
    exit 1
}

die() { echo "ERROR: $1" >&2; exit 1; }

# Runs sqlite3 inside a throwaway container, mounting the db's host directory.
# Usage: sqlite_run <host_db_path> <sql>
sqlite_run() {
    local host_db="$1"
    local sql="$2"
    local host_dir
    host_dir="$(dirname "$host_db")"
    local db_file
    db_file="$(basename "$host_db")"

    docker run --rm \
        -v "${host_dir}:/db" \
        "$SQLITE_IMAGE" \
        sqlite3 "/db/${db_file}" "$sql"
}

# --- Locate the container ----------------------------------------------------

if ! docker inspect "$CONTAINER_NAME" &>/dev/null; then
    CONTAINER_NAME=$(docker ps --format '{{.Names}}\t{{.Image}}' \
        | grep -i audiobookshelf | awk '{print $1}' | head -1 || true)
    [[ -z "$CONTAINER_NAME" ]] && die \
        "No running Audiobookshelf container found. Set ABS_CONTAINER or start the container."
    echo "Auto-detected container: $CONTAINER_NAME"
fi

echo "Using container: $CONTAINER_NAME"

# --- Find the host path of the config volume ---------------------------------
# Inspect the container's mounts to get the real on-disk path for /config.

CONFIG_HOST_PATH=$(docker inspect "$CONTAINER_NAME" \
    --format '{{range .Mounts}}{{if eq .Destination "/config"}}{{.Source}}{{end}}{{end}}')

[[ -z "$CONFIG_HOST_PATH" ]] && die \
    "Could not determine host path for the /config volume. Is it mounted?"

echo "Config volume on host: $CONFIG_HOST_PATH"

# --- Find the database file --------------------------------------------------

DB_HOST_PATH=$(find "$CONFIG_HOST_PATH" -name "absdatabase.sqlite" 2>/dev/null | head -1 || true)

[[ -z "$DB_HOST_PATH" ]] && die \
    "Could not find absdatabase.sqlite under $CONFIG_HOST_PATH"

echo "Database: $DB_HOST_PATH"

# --- Args --------------------------------------------------------------------

if [[ $# -lt 1 ]] then
    echo "Username cannot be empty. Valid options:"
    sqlite_run "$DB_HOST_PATH" "SELECT username FROM users;"
    exit 1
fi
USERNAME="$1"
[[ -z "$USERNAME" ]] && usage

# --- Look up the user --------------------------------------------------------

USER_ROW=$(sqlite_run "$DB_HOST_PATH" \
    "SELECT id, username, type FROM users WHERE username = '${USERNAME}' LIMIT 1;")

[[ -z "$USER_ROW" ]] && die "User '$USERNAME' not found in the database."

USER_ID=$(echo "$USER_ROW" | cut -d'|' -f1)
USER_TYPE=$(echo "$USER_ROW" | cut -d'|' -f3)

echo "Found user: id=$USER_ID  username=$USERNAME  type=$USER_TYPE"

# --- Apply the update --------------------------------------------------------

#sqlite_run "$DB_HOST_PATH" "UPDATE users SET pash = NULL WHERE id = '${USER_ID}';"

# Verify
UPDATED=$(sqlite_run "$DB_HOST_PATH" "SELECT pash FROM users WHERE id = '${USER_ID}';")

[[ -z "$UPDATED" ]] || die "Update verification failed — pash is still set."

echo ""
echo "✓ Password cleared for user '$USERNAME'."
echo ""
echo "Restart the container to ensure sessions are cleared:"
echo "  docker restart $CONTAINER_NAME"

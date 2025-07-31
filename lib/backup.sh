#!/bin/bash

# immich backup script
# 2025-07-31 v1.3

log_prefix() { echo "[$(date '+%Y%m%d %H:%M:%S.%3N')] -"; }

# load env file
ENV_FILE="../.env"
if [ ! -f "$ENV_FILE" ]; then
    echo "$(log_prefix) ERROR: .env file not found at $ENV_FILE"
    exit 1
fi

set -a  # automatically export all variables
source "$ENV_FILE"
set +a  # turn off automatic export

# check env variables
if [ -z "${UPLOAD_LOCATION:-}" ]; then
    echo "$(log_prefix) ERROR: UPLOAD_LOCATION not found in .env file"
    exit 1
fi

if [ -z "${X_BACKUP_VOLUME:-}" ]; then
    echo "$(log_prefix) ERROR: X_BACKUP_VOLUME not found in .env file"
    exit 1
fi

if [ -z "${X_BACKUP_LOCATION:-}" ]; then
    echo "$(log_prefix) ERROR: X_BACKUP_LOCATION not found in .env file"
    exit 1
fi

if [ -z "${DB_USERNAME:-}" ]; then
    echo "$(log_prefix) ERROR: DB_USERNAME not found in .env file"
    exit 1
fi

if [ -z "${DB_PASSWORD:-}" ]; then
    echo "$(log_prefix) ERROR: DB_PASSWORD not found in .env file"
    exit 1
fi

# ensure trailing slash for rsync
case "$UPLOAD_LOCATION" in
    */) ;;
    *) UPLOAD_LOCATION="${UPLOAD_LOCATION}/" ;;
esac

# parse command line arguments
SKIP_DUMP=false
while [[ $# -gt 0 ]]; do
    case $1 in
        --skip-dump)
            SKIP_DUMP=true
            shift
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [--skip-dump]"
            exit 1
            ;;
    esac
done

echo "$(log_prefix) Starting Immich backup process..."

# exit immediately if a command exits with a non-zero status
set -e
# treat unset variables as an error when substituting
set -u
# exit if any command in a pipeline fails
set -o pipefail

# check if external drive is mounted
echo "$(log_prefix) Checking if external drive is mounted at ${X_BACKUP_VOLUME}..."
if ! grep -qs "${X_BACKUP_VOLUME} " /proc/mounts; then
    echo "$(log_prefix) ERROR: External drive ${X_BACKUP_VOLUME} does not appear to be mounted."
    echo "$(log_prefix) Please connect and mount the drive, then re-run the script."
    exit 1
fi
echo "$(log_prefix) External drive found."

# create backup directories if they don't exist
DB_BACKUP_DIR="${X_BACKUP_VOLUME}${X_BACKUP_LOCATION}/db_backups"
UPLOAD_BACKUP_DIR="${X_BACKUP_VOLUME}${X_BACKUP_LOCATION}/upload_backup"

echo "$(log_prefix) Ensuring backup directories exist..."
mkdir -p "${DB_BACKUP_DIR}"
mkdir -p "${UPLOAD_BACKUP_DIR}"
echo "$(log_prefix) Backup directories checked/created."

# database backup (skip if --skip-dump flag is set)
DB_CONTAINER_NAME="immich_postgres"

if [ "$SKIP_DUMP" = false ]; then
    DB_BACKUP_FILE="${DB_BACKUP_DIR}/immich-db-$(date '+%Y%m%d%H%M%S').sql.gz"
    echo "$(log_prefix) Starting database backup for container '${DB_CONTAINER_NAME}'..."
    echo "$(log_prefix) Dumping to ${DB_BACKUP_FILE}..."

    if PGPASSWORD="${DB_PASSWORD}" docker exec -t "${DB_CONTAINER_NAME}" pg_dumpall --clean --if-exists --username="${DB_USERNAME}" | gzip > "${DB_BACKUP_FILE}"; then
        echo "$(log_prefix) Database backup completed successfully."
    else
        echo "$(log_prefix) ERROR: Database backup failed."
        rm -f "${DB_BACKUP_FILE}"
        exit 1
    fi
else
    echo "$(log_prefix) Skipping database backup..."
fi

# assets backup
echo "$(log_prefix) Starting backup of UPLOAD_LOCATION: ${UPLOAD_LOCATION}..."
echo "$(log_prefix) Synchronizing to ${UPLOAD_BACKUP_DIR}..."

# rsync options:
# -a: archive mode (recursive, preserves permissions, symlinks, etc.)
# -v: verbose (shows files being transferred)
# --delete: deletes files in destination that are not in source (makes it a mirror)
# --compress: compresses file data during transfer (can save bandwidth but uses more CPU)
# You can remove --compress if your external drive is fast (e.g., USB 3.0) and CPU is a bottleneck.
# The trailing slash on NAS_UPLOAD_LOCATION is important to copy the *contents* of the directory.
if rsync -av --delete "${UPLOAD_LOCATION}" "${UPLOAD_BACKUP_DIR}/"; then
    echo "$(log_prefix) Uploads/Assets backup completed successfully."
else
    echo "$(log_prefix) ERROR: Uploads/Assets backup failed."
    exit 1
fi

echo "$(log_prefix) Immich backup process finished successfully."
echo "$(log_prefix) Backups are located in: ${BACKUP_BASE_DIR}"

unset DB_PASSWORD
set +e
set +u
set +o pipefail

exit 0

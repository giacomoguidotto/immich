#!/bin/bash

# immich backup script
# 2026-05-05 v2.0

log_prefix() { echo "[$(date '+%Y%m%d %H:%M:%S.%3N')] -"; }

# load env file
ENV_FILE="../.env"
if [ ! -f "$ENV_FILE" ]; then
    echo "$(log_prefix) ERROR: .env file not found at $ENV_FILE"
    exit 1
fi

set -a
source "$ENV_FILE"
set +a

# check env variables
if [ -z "${UPLOAD_LOCATION:-}" ]; then
    echo "$(log_prefix) ERROR: UPLOAD_LOCATION not found in .env file"
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

# detect external drives
EXTERNAL_BASE="/share/external"
echo "$(log_prefix) Detecting external drives at ${EXTERNAL_BASE}..."

DRIVES=()
if [ -d "$EXTERNAL_BASE" ]; then
    for d in "$EXTERNAL_BASE"/*/; do
        [ -d "$d" ] && DRIVES+=("${d%/}")
    done
fi

if [ ${#DRIVES[@]} -eq 0 ]; then
    echo "$(log_prefix) ERROR: No external drives found at ${EXTERNAL_BASE}."
    echo "$(log_prefix) Please connect and mount the drive, then re-run the script."
    exit 1
elif [ ${#DRIVES[@]} -eq 1 ]; then
    X_BACKUP_VOLUME="${DRIVES[0]}"
    echo "$(log_prefix) Found external drive: ${X_BACKUP_VOLUME}"
else
    echo "$(log_prefix) Multiple external drives found:"
    for i in "${!DRIVES[@]}"; do
        echo "  $((i+1))) ${DRIVES[$i]}"
    done
    read -r -p "Select drive [1-${#DRIVES[@]}]: " choice
    if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt ${#DRIVES[@]} ]; then
        echo "$(log_prefix) ERROR: Invalid selection."
        exit 1
    fi
    X_BACKUP_VOLUME="${DRIVES[$((choice-1))]}"
    echo "$(log_prefix) Selected: ${X_BACKUP_VOLUME}"
fi

# show drive info and ask for confirmation
echo ""
echo "── Drive details ──────────────────────────────────────"
echo "  Path:       ${X_BACKUP_VOLUME}"
df -h "${X_BACKUP_VOLUME}" 2>/dev/null | awk 'NR==2 { printf "  Size:       %s\n  Used:       %s (%s)\n  Available:  %s\n", $2, $3, $5, $4 }'
echo "  Backup dir: ${X_BACKUP_VOLUME}${X_BACKUP_LOCATION}"
echo "──────────────────────────────────────────────────────"
echo ""
read -r -p "Proceed with backup to this drive? [y/N] " confirm
if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo "$(log_prefix) Backup cancelled."
    exit 0
fi

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
    DB_BACKUP_FILE="${DB_BACKUP_DIR}/immich-db-latest.sql.gz"
    echo "$(log_prefix) Starting database backup for container '${DB_CONTAINER_NAME}'..."
    echo "$(log_prefix) Dumping to ${DB_BACKUP_FILE}..."

    if docker exec -t "${DB_CONTAINER_NAME}" pg_dumpall --clean --if-exists --username="${DB_USERNAME}" | gzip > "${DB_BACKUP_FILE}"; then
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
echo "$(log_prefix) Backups are located in: ${X_BACKUP_VOLUME}${X_BACKUP_LOCATION}"

# offer to eject the external drive
echo ""
read -r -p "Eject ${X_BACKUP_VOLUME}? [Y/n] " eject
if [[ ! "$eject" =~ ^[Nn]$ ]]; then
    echo "$(log_prefix) Syncing and unmounting ${X_BACKUP_VOLUME}..."
    sync
    if umount "${X_BACKUP_VOLUME}"; then
        echo "$(log_prefix) Drive ejected. Safe to disconnect."
    else
        echo "$(log_prefix) WARNING: Failed to unmount. The drive may still be in use."
    fi
fi

unset DB_PASSWORD
set +e
set +u
set +o pipefail

exit 0

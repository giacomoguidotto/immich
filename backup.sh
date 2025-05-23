#!/bin/bash

# Immich Backup Script for QNAP NAS
# Version 1.1
# Date: 2025-05-23

# --- Configuration ---
# Immich Upload Location on the NAS (Host Path)
# This is the path on your NAS that is mapped to /usr/src/app/upload in the immich-server container.
# Ensure trailing slash for rsync
ORIGINAL_UPLOAD_LOCATION="/share/CACHEDEV3_DATA/immich/upload/"

# external drive mount point (IMPORTANT: Ensure this is correct and the drive is mounted)
EXTERNAL_DRIVE_MOUNT_POINT="/share/external/DEV3304_1"

# Backup base directory on the external drive
BACKUP_BASE_DIR="${EXTERNAL_DRIVE_MOUNT_POINT}/immich"
DB_BACKUP_DIR="${BACKUP_BASE_DIR}/db_backups"
UPLOAD_BACKUP_DIR="${BACKUP_BASE_DIR}/upload_backup"

# immich database container name
DB_CONTAINER_NAME="immich_postgres"

# immich database credentials
# WARNING: Storing passwords in scripts can be a security risk.
# Consider alternatives like .pgpass if this script is stored in an insecure location.
DB_USER="postgres"
DB_PASSWORD="REDACTED"


# --- Script Logic ---
log_prefix() { echo "[$(date '+%Y%m%d %H:%M:%S.%3N')] -"; }

echo "$(log_prefix) Starting Immich backup process..."

# Exit immediately if a command exits with a non-zero status
set -e
# Treat unset variables as an error when substituting
set -u
# Pipestatus (exit if any command in a pipeline fails)
set -o pipefail

# Check if external drive is mounted
echo "$(log_prefix) Checking if external drive is mounted at ${EXTERNAL_DRIVE_MOUNT_POINT}..."
if ! grep -qs "${EXTERNAL_DRIVE_MOUNT_POINT} " /proc/mounts; then
    echo "$(log_prefix) ERROR: External drive ${EXTERNAL_DRIVE_MOUNT_POINT} does not appear to be mounted."
    echo "$(log_prefix) Please connect and mount the drive, then re-run the script."
    exit 1
fi
echo "$(log_prefix) External drive found."

# Create backup directories if they don't exist
echo "$(log_prefix) Ensuring backup directories exist..."
mkdir -p "${DB_BACKUP_DIR}"
mkdir -p "${UPLOAD_BACKUP_DIR}"
echo "$(log_prefix) Backup directories checked/created."

# Database backup
DB_BACKUP_FILE="${DB_BACKUP_DIR}/immich-db-$(date '+%Y%m%d%H%M%S').sql.gz"
echo "$(log_prefix) Starting database backup for container '${DB_CONTAINER_NAME}'..."
echo "$(log_prefix) Dumping to ${DB_BACKUP_FILE}..."

if PGPASSWORD="${DB_PASSWORD}" docker exec -t "${DB_CONTAINER_NAME}" pg_dumpall --clean --if-exists --username="${DB_USER}" | gzip > "${DB_BACKUP_FILE}"; then
    echo "$(log_prefix) Database backup completed successfully."
else
    echo "$(log_prefix) ERROR: Database backup failed."
    rm -f "${DB_BACKUP_FILE}"
    exit 1
fi

# Assets backup
echo "$(log_prefix) Starting backup of UPLOAD_LOCATION: ${ORIGINAL_UPLOAD_LOCATION}..."
echo "$(log_prefix) Synchronizing to ${UPLOAD_BACKUP_DIR}..."

# rsync options:
# -a: archive mode (recursive, preserves permissions, symlinks, etc.)
# -v: verbose (shows files being transferred)
# --delete: deletes files in destination that are not in source (makes it a mirror)
# --compress: compresses file data during transfer (can save bandwidth but uses more CPU)
# You can remove --compress if your external drive is fast (e.g., USB 3.0) and CPU is a bottleneck.
# The trailing slash on NAS_UPLOAD_LOCATION is important to copy the *contents* of the directory.
if rsync -av --delete "${ORIGINAL_UPLOAD_LOCATION}" "${UPLOAD_BACKUP_DIR}/"; then
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

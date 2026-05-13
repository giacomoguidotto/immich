#!/bin/bash

# immich restore script
# 2026-05-13 v1.0

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

# check required env variables
for var in UPLOAD_LOCATION X_BACKUP_LOCATION DB_USERNAME; do
    if [ -z "${!var:-}" ]; then
        echo "$(log_prefix) ERROR: $var not found in .env file"
        exit 1
    fi
done

echo "$(log_prefix) Starting Immich restore process..."

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

# locate backup files on the drive
DB_BACKUP_DIR="${X_BACKUP_VOLUME}${X_BACKUP_LOCATION}/db_backups"
UPLOAD_BACKUP_DIR="${X_BACKUP_VOLUME}${X_BACKUP_LOCATION}/upload_backup"
DB_DUMP="${DB_BACKUP_DIR}/immich-db-latest.sql.gz"

if [ ! -f "$DB_DUMP" ]; then
    echo "$(log_prefix) ERROR: No database dump found at ${DB_DUMP}"
    exit 1
fi

if [ ! -d "$UPLOAD_BACKUP_DIR" ]; then
    echo "$(log_prefix) ERROR: No upload backup found at ${UPLOAD_BACKUP_DIR}"
    exit 1
fi

# show restore plan and ask for confirmation
echo ""
echo "── Restore plan ──────────────────────────────────────"
echo "  Drive:        ${X_BACKUP_VOLUME}"
df -h "${X_BACKUP_VOLUME}" 2>/dev/null | awk 'NR==2 { printf "  Size:         %s\n  Used:         %s (%s)\n", $2, $3, $5 }'
echo "  DB dump:      ${DB_DUMP}"
echo "  Upload src:   ${UPLOAD_BACKUP_DIR}"
echo "  Upload dest:  ${UPLOAD_LOCATION}"
echo "──────────────────────────────────────────────────────"
echo ""
read -r -p "This will overwrite the current database and upload data. Proceed? [y/N] " confirm
if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo "$(log_prefix) Restore cancelled."
    exit 0
fi

# exit immediately if a command exits with a non-zero status
set -e
# treat unset variables as an error when substituting
set -u
# exit if any command in a pipeline fails
set -o pipefail

COMPOSE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DB_CONTAINER_NAME="immich_postgres"

# step 1: stop services
echo "$(log_prefix) Stopping services..."
docker compose -f "${COMPOSE_DIR}/docker-compose.yaml" down 2>/dev/null || true

# step 2: restore upload data (done first — can be large, runs while everything is stopped)
echo "$(log_prefix) Restoring upload data to ${UPLOAD_LOCATION}..."
mkdir -p "${UPLOAD_LOCATION}"
rsync -av --delete "${UPLOAD_BACKUP_DIR}/" "${UPLOAD_LOCATION}/"
echo "$(log_prefix) Upload data restored."

# step 3: start database only
echo "$(log_prefix) Starting database container..."
docker compose -f "${COMPOSE_DIR}/docker-compose.yaml" up -d database

echo "$(log_prefix) Waiting for database to accept connections..."
for i in $(seq 1 60); do
    if docker exec "${DB_CONTAINER_NAME}" pg_isready -U "${DB_USERNAME}" > /dev/null 2>&1; then
        echo "$(log_prefix) Database is ready."
        break
    fi
    if [ "$i" -eq 60 ]; then
        echo "$(log_prefix) ERROR: Database did not become ready within 60 seconds."
        exit 1
    fi
    sleep 1
done

# step 4: restore database
# pg_dumpall output must target the 'postgres' maintenance DB (it drops/creates individual DBs).
# Harmless errors like "role postgres already exists" are expected — do NOT use ON_ERROR_STOP.
echo "$(log_prefix) Restoring database from ${DB_DUMP}..."
echo "$(log_prefix) (harmless warnings like 'role already exists' are expected)"
gunzip -c "${DB_DUMP}" | docker exec -i "${DB_CONTAINER_NAME}" psql -U "${DB_USERNAME}" -d postgres > /dev/null
echo "$(log_prefix) Database restore completed."

# step 5: start all services
echo "$(log_prefix) Starting all services..."
docker compose -f "${COMPOSE_DIR}/docker-compose.yaml" up -d

echo "$(log_prefix) Waiting for Immich to become healthy..."
for i in $(seq 1 120); do
    if docker inspect --format='{{.State.Health.Status}}' immich_server 2>/dev/null | grep -q "healthy"; then
        echo "$(log_prefix) Immich is healthy."
        break
    fi
    if [ "$i" -eq 120 ]; then
        echo "$(log_prefix) WARNING: Immich did not become healthy within 2 minutes."
        echo "$(log_prefix) Check with: docker logs immich_server"
        break
    fi
    sleep 1
done

echo "$(log_prefix) Restore finished. Open the Immich UI and verify photos are browsable."

unset DB_PASSWORD
set +e
set +u
set +o pipefail

exit 0

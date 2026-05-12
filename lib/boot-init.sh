#!/bin/bash
# QNAP boot initialization — restores SSH keys and starts services properly.
# Installed as autorun by: ./deploy.sh --setup
#
# Values below must match deploy.sh defaults.

CONFIG_DIR="/share/immich/config"
NAS_USER="nicagiMaster"
NAS_HOME="/share/homes/${NAS_USER}"
LOG="/var/log/immich-boot-init.log"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG"; }

log "Boot init starting..."

# --- Restore SSH authorized_keys from persistent storage ---
# QNAP wipes /share/homes/ on reboot; keys are kept on the data volume instead.
PERSISTENT_KEYS="${CONFIG_DIR}/.ssh/authorized_keys"
if [ -f "$PERSISTENT_KEYS" ]; then
    mkdir -p "${NAS_HOME}/.ssh"
    chmod 755 "${NAS_HOME}"
    chmod 700 "${NAS_HOME}/.ssh"
    cp "$PERSISTENT_KEYS" "${NAS_HOME}/.ssh/authorized_keys"
    chmod 600 "${NAS_HOME}/.ssh/authorized_keys"
    chown -R "${NAS_USER}:" "${NAS_HOME}/.ssh" 2>/dev/null || true
    log "SSH keys restored."
else
    log "WARNING: No persistent keys at ${PERSISTENT_KEYS}"
fi

# --- Wait for Docker daemon ---
log "Waiting for Docker..."
for i in $(seq 1 30); do
    docker info >/dev/null 2>&1 && break
    sleep 2
done

if ! docker info >/dev/null 2>&1; then
    log "ERROR: Docker not available after 60s, skipping service restart."
    exit 1
fi

# --- Restart services with proper dependency ordering ---
# Docker daemon auto-restarts containers without respecting compose depends_on,
# so we stop and re-start through compose to enforce health-check ordering.
log "Restarting services via docker compose..."
cd "${CONFIG_DIR}" || exit 1
docker compose stop
docker compose up -d
log "Boot init complete."

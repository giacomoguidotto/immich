#!/usr/bin/env bash
set -euo pipefail

# ─── Configuration ───────────────────────────────────────────────
# Override these with environment variables if needed:
#   NAS_HOST=192.168.1.100 ./deploy.sh
NAS_HOST="${NAS_HOST:-nicagi-store01}"
NAS_USER="${NAS_USER:-nicagiMaster}"
NAS_PATH="${NAS_PATH:-/share/immich/config}"
# ─────────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ─── SSH multiplexing (single connection, single auth prompt) ────
CTRL_SOCKET="/tmp/immich-deploy-${NAS_USER}@${NAS_HOST}"
SSH_OPTS="-o ControlMaster=auto -o ControlPath=${CTRL_SOCKET} -o ControlPersist=60s"

cleanup() { ssh -o ControlPath="${CTRL_SOCKET}" -O exit "${NAS_USER}@${NAS_HOST}" 2>/dev/null || true; }
trap cleanup EXIT
# ─────────────────────────────────────────────────────────────────

usage() {
    echo "Usage: $0 [--sync-only | --restart-only | --setup]"
    echo ""
    echo "  (no flags)      Sync files and restart services"
    echo "  --sync-only     Only sync files, don't restart"
    echo "  --restart-only  Only pull images and restart, don't sync"
    echo "  --setup         One-time NAS setup (home dir + SSH key)"
    echo ""
    echo "Environment variables:"
    echo "  NAS_HOST   NAS hostname or IP (default: nicagi-store01)"
    echo "  NAS_USER   SSH username       (default: nicagiMaster)"
    echo "  NAS_PATH   Config path on NAS (default: /share/immich/config)"
}

SYNC=true
RESTART=true
SETUP=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --sync-only)
            RESTART=false
            shift
            ;;
        --restart-only)
            SYNC=false
            shift
            ;;
        --setup)
            SETUP=true
            SYNC=false
            RESTART=false
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

if [ "$SETUP" = true ]; then
    echo "Running one-time NAS setup..."

    NAS_HOME="/share/homes/${NAS_USER}"

    echo "Creating home directory and .ssh directory on NAS..."
    ssh ${SSH_OPTS} "${NAS_USER}@${NAS_HOST}" "\
        mkdir -p ${NAS_HOME}/.ssh && \
        chmod 755 ${NAS_HOME} && \
        chmod 700 ${NAS_HOME}/.ssh"

    echo "Copying SSH public key to NAS..."
    # find the public key configured for this host (falls back to life-auth.pub)
    PUBKEY_FILE="${HOME}/.ssh/life-auth.pub"
    if [ ! -f "$PUBKEY_FILE" ]; then
        echo "ERROR: Public key not found at ${PUBKEY_FILE}"
        exit 1
    fi

    PUBKEY=$(cat "$PUBKEY_FILE")
    ssh ${SSH_OPTS} "${NAS_USER}@${NAS_HOST}" "\
        grep -qF '${PUBKEY}' ${NAS_HOME}/.ssh/authorized_keys 2>/dev/null || \
        echo '${PUBKEY}' >> ${NAS_HOME}/.ssh/authorized_keys && \
        chmod 600 ${NAS_HOME}/.ssh/authorized_keys"

    echo "Setup complete. Testing key-based auth..."
    # close the multiplexed connection so the next one tests fresh auth
    ssh -o ControlPath="${CTRL_SOCKET}" -O exit "${NAS_USER}@${NAS_HOST}" 2>/dev/null || true

    if ssh -o BatchMode=yes "${NAS_USER}@${NAS_HOST}" "echo 'SSH key auth works!'" 2>/dev/null; then
        echo "Key-based authentication is working. No more password prompts."
    else
        echo "WARNING: Key auth test failed. 1Password may need to approve the key."
        echo "Try running: ssh nicagi-store01"
    fi
    exit 0
fi

if [ "$SYNC" = true ]; then
    echo "Syncing config to ${NAS_USER}@${NAS_HOST}:${NAS_PATH}..."
    rsync -avz -e "ssh ${SSH_OPTS}" \
        --exclude='.git/' \
        --exclude='.gitignore' \
        --exclude='.env' \
        --exclude='.env.example' \
        --exclude='deploy.sh' \
        --exclude='ts-state/' \
        --exclude='README.md' \
        "${SCRIPT_DIR}/" "${NAS_USER}@${NAS_HOST}:${NAS_PATH}/"
    echo "Files synced."
fi

if [ "$RESTART" = true ]; then
    echo "Pulling images and restarting services..."
    # bash -l forces a login shell so QNAP's PATH includes docker (from Container Station)
    ssh ${SSH_OPTS} "${NAS_USER}@${NAS_HOST}" "bash -l -c 'cd ${NAS_PATH} && docker compose pull && docker compose up -d'"
    echo "Services restarted."
fi

echo "Done."

# Immich

Docker Compose configuration for [Immich](https://immich.app) running on a QNAP NAS, accessed remotely via [Tailscale](https://tailscale.com) and [Cloudflare Tunnel](https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/).

## 📁 Files

| File                          | Description                                                          |
| ----------------------------- | -------------------------------------------------------------------- |
| `docker-compose.yaml`         | All services: Immich, Tailscale, Cloudflared, Watchtower, Postgres, Redis |
| `.env.example`                | Template for `.env`                                                  |
| `ts-config/serve-config.json` | Tailscale Serve config - HTTPS proxy to Immich                       |
| `lib/immich-config.json`      | Immich application settings                                          |
| `lib/backup.sh`               | Backup script - dumps Postgres + rsyncs uploads to an external drive |
| `deploy.sh`                   | Deploys config to the NAS and manages services                       |

## 🚀 Quick start

Create your .env from the template:

```bash
cp .env.example .env
```

Set up SSH key auth to the NAS:

```bash
./deploy.sh --setup
```

Deploy everything (including .env on first run):

```bash
./deploy.sh
```

> If a local `.env` is present, `deploy.sh` syncs it to the NAS. If not, the NAS `.env` is left untouched, so day-to-day deploys never overwrite your secrets.

```bash
# other commands
./deploy.sh --sync-only       # sync files only, don't restart
./deploy.sh --restart-only    # pull images and restart, no file sync
```

## 🔑 Tailscale key rotation

Auth keys expire every 90 days. Generate a new one at [Tailscale admin](https://login.tailscale.com/admin/settings/keys) (reusable, no expiry on the node), then:

```bash
./deploy.sh --rotate-key tskey-auth-xxxxx
```

## 🔄 Auto-updates

[Watchtower](https://containrrr.dev/watchtower/) checks for new images daily at 4:00 AM. Only labeled containers are updated:

- `tailscale` (`:latest`)
- `immich-server` (`:release`)
- `immich-machine-learning` (`:release`)
- `cloudflared` (`:latest`)

Postgres and Redis are **not** auto-updated (pinned versions to avoid data migration issues).

## 🌐 Custom domain

Immich is accessible via a custom domain through a [Cloudflare Tunnel](https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/). The `cloudflared` container connects outbound to Cloudflare's edge, no inbound ports needed.

To set up, create a tunnel in [Zero Trust](https://one.dash.cloudflare.com/) > Networks > Connectors > Cloudflare Tunnels, then add `CF_TUNNEL_TOKEN` to your `.env`.

## 💾 Backups

```bash
# full backup (database dump + upload rsync to external drive)
ssh <nas-host> "bash -l -c 'cd /share/immich/config/lib && ./backup.sh'"

# skip database dump, only sync uploads
ssh <nas-host> "bash -l -c 'cd /share/immich/config/lib && ./backup.sh --skip-dump'"
```

Requires an external drive mounted at `X_BACKUP_VOLUME` (configured in `.env`).

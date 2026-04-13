# Immich

Docker Compose configuration for [Immich](https://immich.app) running on a QNAP NAS, accessed remotely via [Tailscale](https://tailscale.com).

## Architecture

```
           tailnet (WireGuard)
phone/laptop ──────────────── QNAP NAS
                               ├── tailscale    (VPN + HTTPS reverse proxy)
                               ├── immich       (photo server)
                               ├── machine-learning
                               ├── postgres     (database)
                               ├── redis        (cache)
                               └── watchtower   (auto-updates)
```

Immich is exposed at `https://immich.astrapia-mamba.ts.net` via Tailscale Serve — no ports opened to the internet.

## Files

| File                          | Description                                                                    |
| ----------------------------- | ------------------------------------------------------------------------------ |
| `docker-compose.yaml`         | All services — Immich, Tailscale, Watchtower, Postgres, Redis                  |
| `.env`                        | Secrets and NAS-specific paths (**not tracked in git**, lives only on the NAS) |
| `.env.example`                | Template for `.env`                                                            |
| `ts-config/serve-config.json` | Tailscale Serve config — HTTPS proxy to Immich                                 |
| `lib/immich-config.json`      | Immich application settings                                                    |
| `lib/backup.sh`               | Backup script — dumps Postgres + rsyncs uploads to an external drive           |
| `deploy.sh`                   | Deploys config to the NAS and manages services                                 |

## Quick start

```bash
# 1. create your .env from the template
cp .env.example .env
# ... fill in your values ...

# 2. one-time: set up SSH key auth to the NAS
./deploy.sh --setup

# 3. deploy everything (including .env on first run)
./deploy.sh
```

> If a local `.env` is present, `deploy.sh` syncs it to the NAS. If not, the NAS `.env` is left untouched — so day-to-day deploys never overwrite your secrets.

```bash
# other commands
./deploy.sh --sync-only       # sync files only, don't restart
./deploy.sh --restart-only    # pull images and restart, no file sync
```

## Tailscale key rotation

Auth keys expire every 90 days. Generate a new one at [Tailscale admin](https://login.tailscale.com/admin/settings/keys) (reusable, no expiry on the node), then:

```bash
./deploy.sh --rotate-key tskey-auth-xxxxx
```

## Auto-updates

[Watchtower](https://containrrr.dev/watchtower/) checks for new images daily at 4:00 AM. Only labeled containers are updated:

- `tailscale` (`:latest`)
- `immich-server` (`:release`)
- `immich-machine-learning` (`:release`)

Postgres and Redis are **not** auto-updated (pinned versions to avoid data migration issues).

## Backups

```bash
# full backup (database dump + upload rsync to external drive)
ssh nicagi-store01 "bash -l -c 'cd /share/immich/config/lib && ./backup.sh'"

# skip database dump, only sync uploads
ssh nicagi-store01 "bash -l -c 'cd /share/immich/config/lib && ./backup.sh --skip-dump'"
```

Requires an external drive mounted at `X_BACKUP_VOLUME` (configured in `.env`).

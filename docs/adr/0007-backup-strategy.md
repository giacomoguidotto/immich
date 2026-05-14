# 3-2-1 backup with BorgBackup and Hetzner Storage Box

Backups follow a 3-2-1 strategy: RAID 1 SSDs (live, on-site), external USB HDD (monthly manual rsync, stored off-site), and Hetzner Storage Box (daily automated BorgBackup over SSH). BorgBackup handles deduplication and compression, keeping incremental daily backups small after the initial seed. A systemd timer managed by Ansible runs daily: pg_dump (compressed), then BorgBackup `/data/storage/` to Hetzner over SSH. The external USB drive remains a manual monthly sync for a physically independent off-site copy.

## Off-site storage: Hetzner Storage Box (reaffirmed 2026-05)

Starting tier is BX11 (1 TB, €3.20/mo). When storage needs cross 1 TB, upgrade in-place to BX21 (5 TB, ~€10.90/mo) via the Hetzner Robot panel -- same server, same credentials, no re-seed. Data is expected to surpass 1 TB soon but stay under 2 TB for the foreseeable future.

### Alternatives evaluated

**BorgBackup-native (SSH/SFTP, no tool change):**

| Provider | Capacity | Monthly cost at 1.5 TB | Notes |
|---|---|---|---|
| Hetzner BX21 | 5 TB fixed | ~€10.90 | In-place upgrade from BX11. Overpaying for unused capacity but zero migration cost. |
| BorgBase Medium | 1 TB base, flex to 4 TB | ~€9.33 | Overage at $7/TB/mo. Purpose-built for Borg with append-only mode and monitoring. Small company risk. |
| BorgBase Large | 2 TB base, flex to 8 TB | ~€11.42 | Clean 2 TB ceiling. $150/yr flat. Same small company risk. |
| rsync.net (Borg) | Pay-per-GB, 200 GB min | ~€11 | $0.008/GB/mo, annual billing only. No borg-specific support. Stable 20+ year track record. |

**S3-compatible (requires migrating from BorgBackup to restic + rclone):**

| Provider | Monthly cost at 1.5 TB | Gotchas |
|---|---|---|
| Backblaze B2 | ~€8.25 | Cheapest per-GB. 3x free egress. Tool migration required. |
| Wasabi | ~€9.60 | 1 TB minimum charge, 90-day retention floor, price rising to $7.99/TB in July 2026. |
| Storj Archive | ~€8.25 | Egress at $0.02/GB -- a full 1.5 TB restore costs ~€30. |
| Cloudflare R2 | ~€20.63 | $15/TB/mo. Zero egress but far too expensive for cold backup. |

### Why Hetzner wins

- **No tool migration.** S3-based providers require replacing BorgBackup with restic + rclone, rewriting the backup Ansible role, re-seeding all data, and retesting restore workflows. Not worth the savings (~€2-3/mo).
- **Cost predictability.** Hetzner uses fixed tiers with no per-operation fees, no egress charges, and no fine print (unlike Wasabi's 90-day retention and minimum charge, or Storj's restore egress). Prices have historically dropped, never increased.
- **In-place scaling.** BX11 → BX21 is a panel click, not a migration. BorgBase and rsync.net offer similar convenience but at comparable or higher cost with less headroom.
- **Restore safety.** Unlimited free bandwidth means testing restores costs nothing. Pay-per-egress providers penalize the one operation that matters most in a disaster.

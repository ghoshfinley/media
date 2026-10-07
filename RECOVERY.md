# Recovery & Backup Runbook

How this stack is backed up and how to rebuild it on a fresh machine.

## What lives where

| Thing | Location | In git? |
|---|---|---|
| `docker-compose.yml`, `recyclarr.yml`, `scripts/` (incl. `remote/deploy.sh`), `README.md` | this repo | ✅ yes |
| `.env` (secrets: API keys, VPN keys, passwords, tunnel token) | Nookie `~/media/.env` + your Mac + password manager | ❌ gitignored — keep a copy in your password manager |
| App state: `config/{sonarr,radarr,prowlarr,seerr,maintainerr,qbittorrent,jellyfin,...}` | Nookie `~/media/config/` | ❌ gitignored — covered by the config backup below |
| Host setup (two USB HDDs: library + downloads) | Nookie OS | ✅ `scripts/setup-media-hdds.sh` |
| Media library + downloads | Two local USB HDDs on Nookie — `/mnt/library` (movies+tv) and `/mnt/downloads` | n/a — re-downloadable, no RAID |

## Backups

- **`scripts/backup-config.sh`** runs nightly on Nookie (cron), tars `.env` + `config/`
  (minus regenerable bulk) into **`/mnt/library/backups/media-config-*.tar.gz`**, keeping the last 14.
  It intentionally includes the Sonarr/Radarr/Prowlarr built-in `Backups/` zips, which are
  consistent DB snapshots — use those if a hot-copied sqlite db ever looks off.
- **`scripts/pull-backup.sh`** (run on your Mac) rsyncs those archives to `~/media-backups`,
  so a copy also survives loss of Nookie. Automated via the launchd agent
  `scripts/com.finley.media-backup-pull.plist` (daily 12:30, or on next wake) — install with
  `cp scripts/com.finley.media-backup-pull.plist ~/Library/LaunchAgents/ && launchctl load -w ~/Library/LaunchAgents/com.finley.media-backup-pull.plist`.
  Note: `~/media-backups` is a `--delete` mirror of `/mnt/library/backups`, so nothing else should
  live there (the agent logs to `~/Library/Logs/media-backup-pull.log`).

## Rebuild on a fresh machine

1. **OS prep:** install Docker + Compose.
2. **Storage HDDs:** with the two USB HDDs attached, run `sudo bash scripts/setup-media-hdds.sh`.
   It wipes + ext4-formats both, adds UUID `nofail` fstab entries, and mounts them at
   `/mnt/library` (movies+tv) and `/mnt/downloads`. ⚠️ Destructive — it wipes both drives.
3. **Repo:** `git clone git@github.com:ghoshfinley/media.git ~/media`
4. **Secrets:** restore `~/media/.env` from your password manager (or a backup archive).
5. **App state:** restore `config/` from the newest backup:
   ```
   cd ~/media && tar xzf /path/to/media-config-YYYYMMDD-HHMMSS.tar.gz
   ```
6. **Launch:** `docker compose up -d` (or run `./scripts/remote/deploy.sh` from your Mac).
7. **Re-enable cron jobs:** `crontab -e` →
   ```
   30 4 * * * /home/user/media/scripts/backup-config.sh  >> /home/user/media/scripts/backup.log 2>&1
   */3 * * * * /home/user/media/scripts/disk-guard.sh     >> /home/user/media/scripts/disk-guard.log 2>&1
   ```
   (`disk-guard.sh` protects the downloads disk `/mnt/downloads` in two stages: **pauses**
   qBittorrent downloads below `LOW_GB` free (resumes above `OK_GB`); and below `KILL_GB`,
   **reclaims space by deleting seeding torrents** — highest ratio first, and *only* ones
   already imported by Radarr/Sonarr (the media is already copied to the library disk
   `/mnt/library`, so we lose only the local seed) — until `KILL_TARGET_GB` free. A torrent
   still in an *arr queue is protected. Env-overridable: `GUARD_PATH` `LOW_GB` `OK_GB`
   `KILL_GB` `KILL_TARGET_GB` `DRY_RUN`.)

## Change log — 2026-07-23 (media storage on local USB HDDs)

The media backbone is two 3 TB USB HDDs plugged into Nookie:

- **HDD-A → `/mnt/library`** (movies + tv) — playback reads.
- **HDD-B → `/mnt/downloads`** — torrent scratch, kept on a separate spindle so download
  churn never contends with playback. Imports are **copies, not hardlinks** (by design);
  actively-seeding files cost 2× space (fine on 3 TB). No RAID — media is re-downloadable.
- Both ext4, mounted by UUID (`nofail`) via `scripts/setup-media-hdds.sh`.
- `docker-compose.yml` — bind-mounts `/mnt/library/{tv,movies}` and `/mnt/downloads`;
  container paths are `/data/{tv,movies,tvshows,downloads}`.
- `disk-guard.sh` — guards `/mnt/downloads` (via `GUARD_PATH`).
- `backup-config.sh` / `pull-backup.sh` — backups land in `/mnt/library/backups`.
- **Failover gap:** the library sits on disks captive to Nookie, so it's unreachable if
  Nookie is down, and there's currently no off-Nookie copy of the library. TBD if wanted.

## Change log — 2026-07-04 (app-config fixes)

**App config (Nookie `config/`, covered by backups):**
- **Seerr** `settings.json` — Radarr root `/movies → /data/movies`, Sonarr `/tv → /data/tv`
  (fixed auto-failing requests).
- **Maintainerr** `maintainerr.sqlite` — Rule #2 "Watched Seasons": `sw_watchers` (≥1 ep) →
  `sw_allEpisodesSeenBy` (all eps), so partly-watched seasons aren't deleted.
- **qBittorrent** `qBittorrent.conf` — `connection_speed` 30→100, `max_uploads_per_torrent`
  4→8, `max_connec` 500→800.

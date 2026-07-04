# Recovery & Backup Runbook

How this stack is backed up and how to rebuild it on a fresh machine.

## What lives where

| Thing | Location | In git? |
|---|---|---|
| `docker-compose.yml`, `recyclarr.yml`, `deploy.sh`, `scripts/`, `README.md` | this repo | ✅ yes |
| `.env` (secrets: API keys, VPN keys, passwords, tunnel token) | Nookie `~/media/.env` + your Mac + password manager | ❌ gitignored — keep a copy in your password manager |
| App state: `config/{sonarr,radarr,prowlarr,seerr,maintainerr,qbittorrent,jellyfin,...}` | Nookie `~/media/config/` | ❌ gitignored — covered by the config backup below |
| Host setup (Drobo mount, cifs-utils) | Nookie OS | ❌ documented here |
| Media library | Drobo NAS (`//192.168.0.199/Music/media`) | n/a |

## Backups

- **`scripts/backup-config.sh`** runs nightly on Nookie (cron), tars `.env` + `config/`
  (minus regenerable bulk) into **`/drobo/backups/media-config-*.tar.gz`**, keeping the last 14.
  It intentionally includes the Sonarr/Radarr/Prowlarr built-in `Backups/` zips, which are
  consistent DB snapshots — use those if a hot-copied sqlite db ever looks off.
- **`scripts/pull-backup.sh`** (run on your Mac) rsyncs those archives to `~/media-backups`,
  so a copy also survives loss of the Drobo.

## Rebuild on a fresh machine

1. **OS prep:** install Docker + Compose, and `sudo apt install -y cifs-utils`.
2. **Drobo mount:** add to `/etc/fstab`, then `sudo mount /drobo`:
   ```
   //192.168.0.199/Music/media  /drobo  cifs  guest,vers=1.0,uid=1000,gid=1000,file_mode=0664,dir_mode=0775,nofail,_netdev,iocharset=utf8  0  0
   ```
   (Set a DHCP reservation for the Drobo — MAC `00:1a:62:03:2d:a3` — so `192.168.0.199` stays put.)
3. **Repo:** `git clone git@github.com:ghoshfinley/media.git ~/media`
4. **Secrets:** restore `~/media/.env` from your password manager (or a backup archive).
5. **App state:** restore `config/` from the newest backup:
   ```
   cd ~/media && tar xzf /path/to/media-config-YYYYMMDD-HHMMSS.tar.gz
   ```
6. **Launch:** `docker compose up -d` (or run `./deploy.sh` from your Mac).
7. **Re-enable backups:** `crontab -e` →
   `30 4 * * * /home/user/media/scripts/backup-config.sh >> /home/user/media/scripts/backup.log 2>&1`

## Change log — 2026-07-04 (Drobo migration + fixes)

**Infra (in git):**
- `docker-compose.yml` — added `drobo_tv`/`drobo_movies` CIFS volumes; repointed
  Sonarr/Radarr/Jellyfin at the Drobo; narrowed qBittorrent/Sonarr/Radarr to
  `./media/downloads`. Container paths unchanged (`/data/{tv,movies,downloads}`).

**Nookie host:**
- `/etc/fstab` — Drobo CIFS mount `//192.168.0.199/Music/media → /drobo`.
- Installed `cifs-utils`.

**App config (Nookie `config/`, covered by backups):**
- **Seerr** `settings.json` — Radarr root `/movies → /data/movies`, Sonarr `/tv → /data/tv`
  (fixed auto-failing requests).
- **Maintainerr** `maintainerr.sqlite` — Rule #2 "Watched Seasons": `sw_watchers` (≥1 ep) →
  `sw_allEpisodesSeenBy` (all eps), so partly-watched seasons aren't deleted.
- **qBittorrent** `qBittorrent.conf` — `connection_speed` 30→100, `max_uploads_per_torrent`
  4→8, `max_connec` 500→800.

**Drobo:** reorganized `Music` share into `music/` + `media/{tv,movies}`; copied the ~132 GB library.

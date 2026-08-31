#!/bin/bash
# Nightly config backup: tars .env + app config -> the library disk (HDD-A), with rotation.
# Excludes regenerable bulk (Jellyfin metadata/cache/transcodes, recyclarr guide cache, logs).
# Keeps the *arr built-in Backups/ zips inside the tar for a consistent restore point.
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"   # ~/media on Nookie
DEST="/mnt/library/backups"
STAMP="$(date +%Y%m%d-%H%M%S)"
OUT="$DEST/media-config-$STAMP.tar.gz"
KEEP=14
HA_URL="http://localhost:8123"
notify() { curl -sf --max-time 5 -X POST -H 'Content-Type: application/json' -d "{\"key\":\"$1\",\"title\":\"$2\",\"message\":\"$3\"}" "$HA_URL/api/webhook/media_guard" >/dev/null || true; }

# /mnt/library must actually be the mounted disk before we write into it —
# otherwise mkdir/tar below "succeed" writing to the root disk instead of
# catching the fault (see mount-guard.sh).
if ! mountpoint -q /mnt/library; then
  echo "$(date '+%F %T')  backup FAILED (/mnt/library not mounted)"
  notify backup_nightly "Nookie: nightly config backup FAILED" "/mnt/library is not mounted — see mount-guard alert"
  exit 1
fi

mkdir -p "$DEST"
cd "$REPO"

# tar exit codes: 0 = ok, 1 = warnings (sockets / files changed during read) — acceptable,
# 2+ = fatal. Portainer is root-owned + unreadable and non-critical, so exclude it.
set +e
tar czf "$OUT" \
  --warning=no-file-ignored --warning=no-file-changed \
  --exclude='config/portainer' \
  --exclude='config/recyclarr' \
  --exclude='config/jellyfin/cache' \
  --exclude='config/jellyfin/transcodes' \
  --exclude='config/jellyfin/log' \
  --exclude='config/jellyfin/data/metadata' \
  --exclude='config/jellyfin/data/subtitles' \
  --exclude='config/*/logs' \
  --exclude='*.log' \
  .env config
rc=$?
set -e
if [ "$rc" -gt 1 ]; then
  echo "$(date '+%F %T')  backup FAILED (tar rc=$rc)"
  notify backup_nightly "Nookie: nightly config backup FAILED" "tar exited $rc — check backup.log on Nookie"
  rm -f "$OUT"; exit 1
fi

# Rotate: keep the newest $KEEP archives
ls -1t "$DEST"/media-config-*.tar.gz 2>/dev/null | tail -n +$((KEEP+1)) | xargs -r rm -f

echo "$(date '+%F %T')  backup OK: $OUT ($(du -h "$OUT" | cut -f1))"

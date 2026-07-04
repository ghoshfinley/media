#!/bin/bash
# Nightly config backup: tars .env + app config -> the Drobo, with rotation.
# Excludes regenerable bulk (Jellyfin metadata/cache/transcodes, recyclarr guide cache, logs).
# Keeps the *arr built-in Backups/ zips inside the tar for a consistent restore point.
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"   # ~/media on Nookie
DEST="/drobo/backups"
STAMP="$(date +%Y%m%d-%H%M%S)"
OUT="$DEST/media-config-$STAMP.tar.gz"
KEEP=14

mkdir -p "$DEST"
cd "$REPO"

tar czf "$OUT" \
  --exclude='config/recyclarr' \
  --exclude='config/jellyfin/cache' \
  --exclude='config/jellyfin/transcodes' \
  --exclude='config/jellyfin/log' \
  --exclude='config/jellyfin/data/metadata' \
  --exclude='config/jellyfin/data/subtitles' \
  --exclude='config/*/logs' \
  --exclude='*.log' \
  .env config

# Rotate: keep the newest $KEEP archives
ls -1t "$DEST"/media-config-*.tar.gz 2>/dev/null | tail -n +$((KEEP+1)) | xargs -r rm -f

echo "$(date '+%F %T')  backup OK: $OUT ($(du -h "$OUT" | cut -f1))"

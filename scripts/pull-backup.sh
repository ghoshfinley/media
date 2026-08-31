#!/bin/bash
# Mac-side: pull the latest config backups from Nookie's library disk to a local folder.
# Run periodically (or via launchd) so a copy also lives off Nookie.
set -uo pipefail

DEST="${1:-$HOME/media-backups}"
# LAN IP, not the "nookie" SSH alias — this hits HA's webhook directly over
# HTTP, not through ssh. Same reachability assumption as the rsync below
# (both only work while on the home LAN).
HA_URL="http://192.168.0.181:8123"
notify() { curl -sf --max-time 5 -X POST -H 'Content-Type: application/json' -d "{\"key\":\"$1\",\"title\":\"$2\",\"message\":\"$3\"}" "$HA_URL/api/webhook/media_guard" >/dev/null 2>&1 || true; }

mkdir -p "$DEST"
if ! rsync -av --delete nookie:/mnt/library/backups/ "$DEST/"; then
  echo "$(date '+%F %T')  pull-backup FAILED (rsync)"
  notify backup_pull "Mac: config backup pull FAILED" "rsync from nookie:/mnt/library/backups/ failed — check pull-backup.log"
  exit 1
fi
echo "pulled to $DEST"
ls -1t "$DEST"/media-config-*.tar.gz 2>/dev/null | head -3

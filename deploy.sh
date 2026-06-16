#!/bin/bash
set -euo pipefail

REMOTE="nookie"
REMOTE_DIR="~/media"

echo "==> Syncing files to $REMOTE:$REMOTE_DIR"

rsync -av --checksum \
  docker-compose.yml \
  README.md \
  "$REMOTE:$REMOTE_DIR/"

rsync -av --checksum --delete \
  config/homepage/ \
  "$REMOTE:$REMOTE_DIR/config/homepage/"

if ! ssh "$REMOTE" "test -f $REMOTE_DIR/.env"; then
  echo ""
  echo "WARNING: No .env found on $REMOTE. Copy and fill in credentials:"
  echo "  scp .env.example $REMOTE:$REMOTE_DIR/.env"
  echo "  ssh $REMOTE 'nano $REMOTE_DIR/.env'"
  exit 1
fi

echo ""
echo "==> Checking for active Jellyfin streams"
JELLYFIN_KEY=$(ssh "$REMOTE" "grep '^JELLYFIN_API_KEY' $REMOTE_DIR/.env | cut -d= -f2")
ACTIVE_STREAMS=$(ssh "$REMOTE" "curl -sf 'http://localhost:8096/Sessions?api_key=$JELLYFIN_KEY&activeWithinSeconds=30' 2>/dev/null | grep -c 'NowPlayingItem' || echo 0")

if [ "$ACTIVE_STREAMS" -gt 0 ]; then
  echo "  WARNING: $ACTIVE_STREAMS active stream(s) detected — skipping Jellyfin pull/restart"
  SKIP_JELLYFIN=true
else
  echo "  No active streams"
  SKIP_JELLYFIN=false
fi

echo ""
echo "==> Pulling latest images on $REMOTE"
if [ "$SKIP_JELLYFIN" = true ]; then
  SERVICES=$(ssh "$REMOTE" "cd $REMOTE_DIR && docker compose config --services | grep -v '^jellyfin$' | tr '\n' ' '")
  ssh "$REMOTE" "cd $REMOTE_DIR && docker compose pull $SERVICES"
else
  ssh "$REMOTE" "cd $REMOTE_DIR && docker compose pull"
fi

echo ""
echo "==> Restarting stack on $REMOTE"
ssh "$REMOTE" "cd $REMOTE_DIR && docker compose up -d"

if [ "$SKIP_JELLYFIN" = true ]; then
  echo ""
  echo "  NOTE: Jellyfin was not updated. Re-run deploy when no streams are active to apply any Jellyfin updates."
fi

echo ""
echo "==> Done"

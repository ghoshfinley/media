#!/bin/bash
set -euo pipefail

REMOTE="nookie"
REMOTE_DIR="~/media"

echo "==> Syncing files to $REMOTE:$REMOTE_DIR"

# Sync compose file and readme
rsync -av --checksum \
  docker-compose.yml \
  README.md \
  "$REMOTE:$REMOTE_DIR/"

# Sync homepage config (fully managed locally)
rsync -av --checksum --delete \
  config/homepage/ \
  "$REMOTE:$REMOTE_DIR/config/homepage/"

# Warn if .env doesn't exist on remote
if ! ssh "$REMOTE" "test -f $REMOTE_DIR/.env"; then
  echo ""
  echo "WARNING: No .env found on $REMOTE. Copy and fill in credentials:"
  echo "  scp .env.example $REMOTE:$REMOTE_DIR/.env"
  echo "  ssh $REMOTE 'nano $REMOTE_DIR/.env'"
  exit 1
fi

echo ""
echo "==> Pulling latest images on $REMOTE"
ssh "$REMOTE" "cd $REMOTE_DIR && docker compose pull"

echo ""
echo "==> Restarting stack on $REMOTE"
ssh "$REMOTE" "cd $REMOTE_DIR && docker compose up -d"

echo ""
echo "==> Done"

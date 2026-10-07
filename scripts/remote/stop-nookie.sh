#!/usr/bin/env bash
# Gracefully stop the Nookie media stack -- run from your laptop, drives it over SSH.
#
# The 90s stop timeout is the point: qBittorrent (libtorrent) needs time to write
# its .fastresume state on SIGTERM, or every torrent gets force-rechecked on next
# start - hours of disk grind. The *arr apps + Jellyfin checkpoint their SQLite
# WALs on the same signal. Drives stay mounted (fstab remounts on boot); after
# this returns it's safe to reboot/poweroff. Bring it back with start-nookie.sh.
set -euo pipefail

REMOTE="nookie"
REMOTE_DIR="~/media"

echo "==> Stopping stack on $REMOTE (up to 90s for qBittorrent to flush fastresume) ..."
ssh "$REMOTE" "cd $REMOTE_DIR && docker compose stop -t 90 && sync"

echo "==> Stopped. Safe to reboot/poweroff $REMOTE. Restart: scripts/remote/start-nookie.sh"

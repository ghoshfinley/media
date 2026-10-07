#!/usr/bin/env bash
# Start the Nookie media stack -- run from your laptop, drives it over SSH.
#
# fstab (nofail) mounts the two USB HDDs on boot, so they're normally present.
# We hard-check them first so containers never bind-mount empty dirs; if one is
# missing, mount it on Nookie (sudo mount /mnt/...) or reboot, then re-run.
# Compose's depends_on brings the VPN up healthy before the services sharing its
# network namespace (qbittorrent, sonarr, radarr, prowlarr, flaresolverr, recyclarr).
set -euo pipefail

REMOTE="nookie"
REMOTE_DIR="~/media"

echo "==> Checking media disks on $REMOTE"
for m in /mnt/library /mnt/downloads; do
  if ! ssh "$REMOTE" "mountpoint -q $m"; then
    echo "  !! $m not mounted on $REMOTE - mount it (sudo mount $m) or reboot, then re-run"
    exit 1
  fi
done

echo "==> Starting stack on $REMOTE ..."
ssh "$REMOTE" "cd $REMOTE_DIR && docker compose up -d"

echo "==> Up. Status: ssh $REMOTE 'cd $REMOTE_DIR && docker compose ps'"

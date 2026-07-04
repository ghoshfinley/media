#!/bin/bash
# Mac-side: pull the latest config backups from Nookie's Drobo to a local folder.
# Run periodically (or via launchd) so a copy also lives off Nookie AND off the Drobo.
set -euo pipefail

DEST="${1:-$HOME/media-backups}"
mkdir -p "$DEST"
rsync -av --delete nookie:/drobo/backups/ "$DEST/"
echo "pulled to $DEST"
ls -1t "$DEST"/media-config-*.tar.gz 2>/dev/null | head -3

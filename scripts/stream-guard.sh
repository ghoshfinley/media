#!/bin/bash
# stream-guard.sh — pause Radarr & Sonarr while Jellyfin is actively streaming.
# The download churn lives on a separate spindle (HDD-B), but an *arr
# import still writes the finished file to the library disk (HDD-A) that playback
# reads from — this pauses those import writes during a stream to keep it smooth.
# Runs from cron every minute on Nookie. Optional; harmless to disable.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
JF_TOKEN=$(grep '^JELLYFIN_API_KEY' "$REPO/.env" | cut -d= -f2)
STATE="$REPO/scripts/.stream-guard-paused"
CONTAINERS="radarr sonarr"

active_streams=$(curl -sf -H "X-Emby-Token: ${JF_TOKEN}" \
    http://localhost:8096/Sessions | \
    python3 -c "
import sys, json
try:
    sessions = json.load(sys.stdin)
    print(sum(1 for s in sessions if s.get('NowPlayingItem')))
except Exception:
    print(0)
")

if [ "${active_streams:-0}" -gt 0 ]; then
    for c in $CONTAINERS; do
        if [ "$(docker inspect -f '{{.State.Status}}' "$c" 2>/dev/null)" = "running" ]; then
            docker pause "$c" >/dev/null
            echo "$(date '+%F %T')  STREAMING (${active_streams}) — paused $c"
            touch "$STATE"
        fi
    done
elif [ -f "$STATE" ]; then
    for c in $CONTAINERS; do
        if [ "$(docker inspect -f '{{.State.Status}}' "$c" 2>/dev/null)" = "paused" ]; then
            docker unpause "$c" >/dev/null
            echo "$(date '+%F %T')  IDLE — unpaused $c"
        fi
    done
    rm -f "$STATE"
fi

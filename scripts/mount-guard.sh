#!/bin/bash
# mount-guard.sh — alerts when /mnt/library or /mnt/downloads drop off the
# host (USB enumeration blip, drive fault, etc). A dropped mount doesn't stop
# the containers — they keep running against the now-dead bind mount and
# throw I/O errors deep in playback/import instead — so nothing else in the
# stack surfaces this on its own. See 2026-08-30 outage: both drives sat
# unmounted for ~18h before anyone noticed via a Jellyfin "fatal playback
# error".
# Runs from cron every few minutes. Logs only on state change (up->down,
# down->up) so the log doesn't spam every run while a fault is ongoing, and
# reports the same transitions to Home Assistant (push notification +
# persistent notification — see media_guard_health.yaml in the mono repo)
# so it doesn't sit unnoticed like the 2026-08-30 outage did.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
STATE="$REPO/scripts/.mount-guard-down"
HA_URL="http://localhost:8123"
LOG() { echo "$(date '+%F %T')  $*"; }
notify()  { curl -sf --max-time 5 -X POST -H 'Content-Type: application/json' -d "{\"key\":\"$1\",\"title\":\"$2\",\"message\":\"$3\"}" "$HA_URL/api/webhook/media_guard" >/dev/null || true; }
resolve() { curl -sf --max-time 5 -X POST -H 'Content-Type: application/json' -d "{\"key\":\"$1\"}" "$HA_URL/api/webhook/media_guard_clear" >/dev/null || true; }

down=""
for m in /mnt/library /mnt/downloads; do
  mountpoint -q "$m" || down="$down $m"
done

if [ -n "$down" ]; then
  if [ ! -f "$STATE" ]; then
    msg="$down not mounted. Fix: ssh nookie 'sudo mount -a' then docker restart jellyfin sonarr radarr (or whichever containers touch the affected disk)"
    LOG "DOWN —$msg"
    notify mount "Nookie: drive dropped" "$msg"
    touch "$STATE"
  fi
else
  if [ -f "$STATE" ]; then
    LOG "RECOVERED — library/downloads mounted again"
    resolve mount
    rm -f "$STATE"
  fi
fi

#!/bin/bash
# Disk safety net: pause qBittorrent downloads when Nookie's root disk gets low,
# resume them once it recovers. Prevents a full disk from taking the server down.
# Runs from cron every few minutes. Only pauses/resumes the torrents IT paused.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
LOW_GB=${LOW_GB:-25}   # pause active downloads when free space drops below this
OK_GB=${OK_GB:-50}     # resume once free space climbs back above this (hysteresis)
STATE="$REPO/scripts/.disk-guard-paused"
Q="http://localhost:8090"

free_gb=$(df -BG --output=avail / | tail -1 | tr -dc '0-9')

PW=$(grep '^QBITTORRENT_PASSWORD' "$REPO/.env" | cut -d= -f2)
CJ=$(mktemp)
trap 'rm -f "$CJ"' EXIT
curl -s -c "$CJ" -d "username=admin&password=$PW" "$Q/api/v2/auth/login" >/dev/null

if [ "$free_gb" -lt "$LOW_GB" ] && [ ! -f "$STATE" ]; then
  # Grab hashes of everything still downloading (leave user-paused / seeding alone)
  hashes=$(curl -s -b "$CJ" "$Q/api/v2/torrents/info?filter=downloading" \
           | python3 -c 'import sys,json;print("|".join(t["hash"] for t in json.load(sys.stdin)))')
  if [ -n "$hashes" ]; then
    curl -s -b "$CJ" "$Q/api/v2/torrents/stop" --data "hashes=$hashes" >/dev/null
    printf '%s\n' "$hashes" > "$STATE"
    n=$(printf '%s' "$hashes" | tr '|' '\n' | grep -c .)
    echo "$(date '+%F %T')  LOW ${free_gb}G < ${LOW_GB}G — paused $n download(s)"
  fi
elif [ "$free_gb" -ge "$OK_GB" ] && [ -f "$STATE" ]; then
  curl -s -b "$CJ" "$Q/api/v2/torrents/start" --data "hashes=$(cat "$STATE")" >/dev/null
  rm -f "$STATE"
  echo "$(date '+%F %T')  OK ${free_gb}G ≥ ${OK_GB}G — resumed downloads"
fi

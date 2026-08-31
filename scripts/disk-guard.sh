#!/bin/bash
# Disk safety net for Nookie's downloads disk (HDD-B, /mnt/downloads):
#   1) pause qBittorrent downloads when free space is low (resume when recovered)
#   2) if CRITICALLY low, reclaim space by deleting seeding torrents — highest ratio
#      first (most "done" seeding), and ONLY ones already imported by Radarr/Sonarr.
#      A torrent still in an *arr queue is downloading or awaiting import, so it's
#      protected; only torrents absent from both queues (= imported, media already
#      copied to the library disk /mnt/library) are deletable. We lose the local
#      seed on HDD-B, never the library copy on HDD-A.
# Runs from cron every few minutes. Env-overridable: GUARD_PATH LOW_GB OK_GB KILL_GB
# KILL_TARGET_GB DRY_RUN. Deletions (but not pause/resume) push a Home Assistant
# notification — see media_guard_health.yaml in the mono repo.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
GUARD_PATH=${GUARD_PATH:-/mnt/downloads}   # disk to watch (torrent downloads live here)
LOW_GB=${LOW_GB:-40}                   # pause downloads below this (backstop once seeds exhausted)
OK_GB=${OK_GB:-55}                     # resume downloads above this
KILL_GB=${KILL_GB:-50}                 # 50G buffer: delete imported seeds when free drops below this
KILL_TARGET_GB=${KILL_TARGET_GB:-60}   # delete seeds until free reaches this
DRY_RUN=${DRY_RUN:-}                    # non-empty = log what would be deleted, don't delete
STATE="$REPO/scripts/.disk-guard-paused"
Q="http://localhost:8090"
HA_URL="http://localhost:8123"
notify() { curl -sf --max-time 5 -X POST -H 'Content-Type: application/json' -d "{\"key\":\"$1\",\"title\":\"$2\",\"message\":\"$3\"}" "$HA_URL/api/webhook/media_guard" >/dev/null || true; }

freegb() { df -BG --output=avail "$GUARD_PATH" | tail -1 | tr -dc '0-9'; }
free=$(freegb)

PW=$(grep '^QBITTORRENT_PASSWORD' "$REPO/.env" | cut -d= -f2)
CJ=$(mktemp); trap 'rm -f "$CJ"' EXIT
curl -s -c "$CJ" -d "username=admin&password=$PW" "$Q/api/v2/auth/login" >/dev/null

# --- 1) pause / resume downloads ---
if [ "$free" -lt "$LOW_GB" ] && [ ! -f "$STATE" ]; then
  hashes=$(curl -s -b "$CJ" "$Q/api/v2/torrents/info?filter=downloading" \
           | python3 -c 'import sys,json;print("|".join(t["hash"] for t in json.load(sys.stdin)))')
  if [ -n "$hashes" ]; then
    curl -s -b "$CJ" "$Q/api/v2/torrents/stop" --data "hashes=$hashes" >/dev/null
    printf '%s\n' "$hashes" > "$STATE"
    echo "$(date '+%F %T')  LOW ${free}G<${LOW_GB}G — stopped downloads"
  fi
elif [ "$free" -ge "$OK_GB" ] && [ -f "$STATE" ]; then
  curl -s -b "$CJ" "$Q/api/v2/torrents/start" --data "hashes=$(cat "$STATE")" >/dev/null
  rm -f "$STATE"
  echo "$(date '+%F %T')  OK ${free}G — resumed downloads"
fi

# --- 2) critically low: delete imported seeds (highest ratio first) to reclaim space ---
if [ "$free" -lt "$KILL_GB" ]; then
  SK=$(grep '^SONARR_API_KEY' "$REPO/.env" | cut -d= -f2)
  RK=$(grep '^RADARR_API_KEY' "$REPO/.env" | cut -d= -f2)
  # download hashes still in an *arr queue = NOT yet imported (protect these)
  pending=$( { curl -s "http://localhost:8989/api/v3/queue?pageSize=1000" -H "X-Api-Key: $SK"; echo;
               curl -s "http://localhost:7878/api/v3/queue?pageSize=1000" -H "X-Api-Key: $RK"; } \
    | python3 -c '
import sys, json
ids = set()
for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    try:
        d = json.loads(line)
    except Exception:
        continue
    for r in d.get("records", []):
        dl = r.get("downloadId")
        if dl:
            ids.add(dl.upper())
print(" ".join(ids))
')
  # seeding torrents, highest ratio first: "HASH_UPPER hash ratio sizeGB name"
  seeds=$(curl -s -b "$CJ" "$Q/api/v2/torrents/info?filter=seeding" | python3 -c '
import sys, json
for t in sorted(json.load(sys.stdin), key=lambda x: x["ratio"], reverse=True):
    print(t["hash"].upper(), t["hash"], round(t["ratio"], 2), round(t["size"]/1e9, 1),
          t["name"][:45].replace(" ", "_"))
')
  deleted_any=0
  while read -r HU h ratio sizegb name; do
    [ -z "${h:-}" ] && continue
    free=$(freegb)
    [ "$free" -ge "$KILL_TARGET_GB" ] && break
    case " $pending " in *" $HU "*) continue ;; esac   # not imported yet — skip
    if [ -n "$DRY_RUN" ]; then
      echo "$(date '+%F %T')  DRY: would delete imported seed ratio=$ratio ${sizegb}G $name (free ${free}G)"
    else
      curl -s -b "$CJ" "$Q/api/v2/torrents/delete" --data "hashes=$h&deleteFiles=true" >/dev/null
      echo "$(date '+%F %T')  CRITICAL ${free}G<${KILL_GB}G — deleted imported seed ratio=$ratio ${sizegb}G $name"
      notify "diskguard_$(date +%s%N)" "Nookie: disk-guard reclaimed space" \
        "Deleted seeding torrent to free space (${free}G < ${KILL_GB}G): $name (ratio $ratio, ${sizegb}G)"
      deleted_any=1
      sleep 2
    fi
  done <<EOF_SEEDS
$seeds
EOF_SEEDS

  # Still critical but nothing was reclaimable (every seed is awaiting import):
  # hold downloads paused so Radarr/Sonarr can catch up on imports — then a later
  # run deletes those seeds once they're imported.
  free=$(freegb)
  if [ -z "$DRY_RUN" ] && [ "$free" -lt "$KILL_GB" ] && [ "$deleted_any" -eq 0 ]; then
    dl=$(curl -s -b "$CJ" "$Q/api/v2/torrents/info?filter=downloading" \
         | python3 -c 'import sys,json;print("|".join(t["hash"] for t in json.load(sys.stdin)))')
    if [ -n "$dl" ]; then
      curl -s -b "$CJ" "$Q/api/v2/torrents/stop" --data "hashes=$dl" >/dev/null
      printf '%s\n' "$dl" > "$STATE"
    fi
    echo "$(date '+%F %T')  CRITICAL ${free}G — all seeds awaiting import; holding downloads for Radarr/Sonarr to import (seeds become reclaimable once imported)"
  fi
fi

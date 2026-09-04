#!/bin/bash
# stalled-guard.sh — catches torrents that are grabbed but never actually
# download because the swarm has no reachable peers (0 seeds, 0 speed,
# 0 progress) for a sustained period, and gets Sonarr/Radarr to try a
# different release instead. Seen 2026-09-04: EZTV grabbed fresh episodes
# of two thinly-seeded shows (The Challenge, Dancing with the Stars: The
# Next Pro) that sat at 0% for 2-3 days with no error ever surfaced —
# qBittorrent doesn't give up on a 0-seed torrent on its own, and Sonarr
# has no "this will never finish" detector, so nothing else in the stack
# would catch this.
# State-tracked (a torrent must be stuck across multiple runs before we
# act, not just momentarily 0 seeds right after grab) via one timestamp
# file per hash in STATE_DIR. Excludes paused/stopped torrents (disk-guard
# pauses those intentionally under low space — not the same as stuck).
#
# Before blocklisting anything, checks gluetun's actual forwarded port
# against qBittorrent's configured listen port. If they don't match (or
# there's no forwarded port at all), 0-seed torrents don't mean "this
# release is dead" — they mean our own connectivity is broken, and every
# active download looks identical to a dead release in that case. Seen
# 2026-08-21 -> 2026-09-04: port forwarding silently died for 2 weeks: had
# this guard existed then, it would have wrongly blocklisted good releases
# across the whole library instead of catching an infra fault. Deferring
# is log-only, not pushed — qbt-healer (see docker-compose.yml) already
# owns alerting on VPN health; this would just duplicate that.
#
# Runs from cron every few minutes. Env-overridable: STALE_HOURS DRY_RUN.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
STALE_HOURS=${STALE_HOURS:-6}
DRY_RUN=${DRY_RUN:-}
STATE_DIR="$REPO/scripts/.stalled-guard-state"
Q="http://localhost:8090"
HA_URL="http://localhost:8123"
mkdir -p "$STATE_DIR"
LOG() { echo "$(date '+%F %T')  $*"; }
notify() { curl -sf --max-time 5 -X POST -H 'Content-Type: application/json' -d "{\"key\":\"$1\",\"title\":\"$2\",\"message\":\"$3\"}" "$HA_URL/api/webhook/media_guard" >/dev/null || true; }

PW=$(grep '^QBITTORRENT_PASSWORD' "$REPO/.env" | cut -d= -f2)
SK=$(grep '^SONARR_API_KEY' "$REPO/.env" | cut -d= -f2)
RK=$(grep '^RADARR_API_KEY' "$REPO/.env" | cut -d= -f2)
CJ=$(mktemp); trap 'rm -f "$CJ"' EXIT
curl -s -c "$CJ" -d "username=admin&password=$PW" "$Q/api/v2/auth/login" >/dev/null

vpn_port_ok() {
  fport=$(docker exec vpn cat /tmp/gluetun/forwarded_port 2>/dev/null)
  [ -z "$fport" ] && return 1
  [ "$fport" = "0" ] && return 1
  qport=$(curl -s -b "$CJ" "$Q/api/v2/app/preferences" | python3 -c 'import json,sys
try:
    print(json.load(sys.stdin).get("listen_port",""))
except Exception:
    pass' 2>/dev/null)
  [ "$fport" = "$qport" ]
}
if vpn_port_ok; then
  VPN_OK=1
else
  VPN_OK=0
  LOG "VPN port forwarding looks unhealthy (forwarded=${fport:-none} qbittorrent=${qport:-?}) — deferring any blocklist actions this run"
fi

# "hash name" for torrents that are actively trying but making zero progress
stuck=$(curl -s -b "$CJ" "$Q/api/v2/torrents/info" | python3 -c '
import sys, json
active = {"downloading","stalledDL","metaDL","queuedDL","error"}
for t in json.load(sys.stdin):
    if t.get("category") not in ("tv-sonarr", "radarr"):
        continue
    if t.get("state") not in active:
        continue
    if t.get("progress", 1) == 0 and t.get("num_seeds", 1) == 0 and t.get("dlspeed", 1) == 0:
        print(t["hash"], t["name"].replace(" ", "_"))
')

now=$(date +%s)
seen_now=""

while read -r h name; do
  [ -z "${h:-}" ] && continue
  seen_now="$seen_now $h"
  f="$STATE_DIR/$h"
  if [ ! -f "$f" ]; then
    echo "$now" > "$f"
    continue
  fi
  first=$(cat "$f" 2>/dev/null || echo "$now")
  elapsed=$(( (now - first) / 3600 ))
  [ "$elapsed" -lt "$STALE_HOURS" ] && continue

  if [ "$VPN_OK" -eq 0 ]; then
    LOG "would act on stalled torrent but VPN port is unhealthy, deferring :: $name (stuck ${elapsed}h)"
    continue
  fi

  if [ -n "$DRY_RUN" ]; then
    LOG "DRY: would remove stalled torrent (stuck ${elapsed}h, 0 seeds) :: $name"
    continue
  fi

  HU=$(echo "$h" | tr a-z A-Z)
  for portkey in "8989:$SK" "7878:$RK"; do
    port=${portkey%%:*}; key=${portkey##*:}
    qid=$(curl -s "http://localhost:$port/api/v3/queue?pageSize=1000" -H "X-Api-Key: $key" \
          | python3 -c "
import json,sys
d=json.load(sys.stdin)
for r in d.get('records',[]):
    if (r.get('downloadId') or '').upper() == '$HU':
        print(r['id']); break
" 2>/dev/null)
    if [ -n "$qid" ]; then
      curl -s -X DELETE "http://localhost:$port/api/v3/queue/$qid?removeFromClient=true&blocklist=true&skipRedownload=false" \
        -H "X-Api-Key: $key" >/dev/null
      LOG "removed+blocklisted stalled queue item $qid on :$port :: $name (stuck ${elapsed}h)"
    fi
  done
  curl -s -b "$CJ" "$Q/api/v2/torrents/delete" --data "hashes=$h&deleteFiles=true" >/dev/null
  notify "stalled_$(date +%s%N)" "Nookie: stalled download replaced" \
    "$name had 0 seeds for ${elapsed}h — removed, blocklisted, searching for a different release"
  rm -f "$f"
done <<EOF_STUCK
$stuck
EOF_STUCK

# Clean up state for hashes that recovered (found peers) or are gone
for f in "$STATE_DIR"/*; do
  [ -e "$f" ] || continue
  h=$(basename "$f")
  case " $seen_now " in *" $h "*) ;; *) rm -f "$f" ;; esac
done

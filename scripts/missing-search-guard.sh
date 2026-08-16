#!/bin/bash
# Retries missing/monitored content in Sonarr & Radarr on a schedule.
# Neither app has a built-in periodic "search missing" task (only RSS sync,
# which only catches new releases posted after last check) — so a grab that
# fails once (e.g. an indexer's temporary rate-limit backoff) never gets
# retried on its own. This re-triggers the search so it eventually succeeds
# once the indexer recovers.
# Runs from cron hourly.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
SK=$(grep '^SONARR_API_KEY' "$REPO/.env" | cut -d= -f2)
RK=$(grep '^RADARR_API_KEY' "$REPO/.env" | cut -d= -f2)

curl -s -X POST 'http://localhost:8989/api/v3/command' \
  -H "X-Api-Key: $SK" -H 'Content-Type: application/json' \
  -d '{"name":"MissingEpisodeSearch"}' >/dev/null
echo "$(date '+%F %T')  triggered Sonarr MissingEpisodeSearch"

curl -s -X POST 'http://localhost:7878/api/v3/command' \
  -H "X-Api-Key: $RK" -H 'Content-Type: application/json' \
  -d '{"name":"MissingMoviesSearch"}' >/dev/null
echo "$(date '+%F %T')  triggered Radarr MissingMoviesSearch"

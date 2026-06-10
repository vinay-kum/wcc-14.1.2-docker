#!/usr/bin/env bash
# Cold snapshot of the WCC playground state (domain + DB) so you can restore to a
# known-good point instead of rebootstrapping. Captures the two named volumes:
#   wcc14_wcc-userprojects  (WCC domain: config, installed components, secret)
#   wcc14_oradata           (Oracle DB: RCU schemas + content)
#
# Snapshots are taken COLD (stack stopped gracefully) so the DB datafiles and WCC
# persistent stores are consistent. Stored under ./snapshots/<name>/.
#
#   scripts/snapshot.sh [name]        # default name = snapshot-<timestamp>
#
# Restore with scripts/restore.sh <name>.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
NAME="${1:-snapshot-$(date +%Y%m%d-%H%M%S)}"
VOLS=(wcc14_wcc-userprojects wcc14_oradata)
DEST="$ROOT/snapshots/$NAME"
STOP_TIMEOUT="${STOP_TIMEOUT:-90}"   # give the Oracle DB time for a clean shutdown

for v in "${VOLS[@]}"; do
  docker volume inspect "$v" >/dev/null 2>&1 || { echo "ERROR: volume $v not found"; exit 1; }
done
mkdir -p "$DEST"

echo "==> Snapshot '$NAME'  ->  $DEST"
echo "==> Stopping stack gracefully (-t $STOP_TIMEOUT) for a consistent cold copy..."
docker compose stop -t "$STOP_TIMEOUT"

for v in "${VOLS[@]}"; do
  echo "==> Archiving $v ..."
  docker run --rm -v "$v":/v:ro -v "$DEST":/b alpine sh -c "tar czf /b/$v.tgz -C /v ."
  echo "    $(du -h "$DEST/$v.tgz" | cut -f1)  $v.tgz"
done

{
  echo "name=$NAME"
  echo "created=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "git_rev=$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || echo n/a)"
  echo "volumes=${VOLS[*]}"
} > "$DEST/manifest.txt"
echo "==> manifest:"; sed 's/^/    /' "$DEST/manifest.txt"

echo "==> Restarting stack..."
docker compose start
echo "==> Snapshot complete. Restore later with:  scripts/restore.sh $NAME"

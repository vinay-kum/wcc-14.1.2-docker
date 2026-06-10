#!/usr/bin/env bash
# Restore the WCC playground to a snapshot taken by scripts/snapshot.sh.
# OVERWRITES the current domain + DB volumes with the snapshot's contents.
#
#   scripts/restore.sh <name>          # prompts for confirmation
#   FORCE=1 scripts/restore.sh <name>  # skip the prompt
#
# After restore, UCM takes a few minutes to come ready; the native CS commands
# (ComponentTool/IdcCommand) regenerate shortly AFTER /weblogic/ready=200.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
NAME="${1:?usage: scripts/restore.sh <snapshot-name>}"
SRC="$ROOT/snapshots/$NAME"
VOLS=(wcc14_wcc-userprojects wcc14_oradata)

[ -d "$SRC" ] || { echo "ERROR: no snapshot at $SRC"; ls "$ROOT/snapshots" 2>/dev/null; exit 1; }
for v in "${VOLS[@]}"; do
  [ -f "$SRC/$v.tgz" ] || { echo "ERROR: missing $SRC/$v.tgz"; exit 1; }
done

echo "==> Restore '$NAME' — this OVERWRITES the live WCC domain + DB."
[ -f "$SRC/manifest.txt" ] && sed 's/^/    /' "$SRC/manifest.txt"
if [ "${FORCE:-0}" != "1" ]; then
  read -r -p "    Type 'yes' to proceed: " ans
  [ "$ans" = "yes" ] || { echo "aborted."; exit 1; }
fi

echo "==> Stopping + removing containers (named volumes are kept, then overwritten)..."
docker compose down

for v in "${VOLS[@]}"; do
  echo "==> Restoring $v ..."
  docker volume create "$v" >/dev/null
  docker run --rm -v "$v":/v -v "$SRC":/b:ro alpine sh -c \
    "find /v -mindepth 1 -delete 2>/dev/null; tar xzf /b/$v.tgz -C /v"
done

echo "==> Bringing stack up..."
docker compose up -d
echo "==> Restore done. Watch: docker compose logs -f wcc-content   (UCM ready in a few min)"

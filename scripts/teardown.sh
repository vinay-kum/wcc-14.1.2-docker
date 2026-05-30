#!/usr/bin/env bash
# Tear down everything: stops + removes containers AND volumes.
# Use this when you want a clean re-bootstrap (RCU + domain re-creation).
set -euo pipefail

cd "$(dirname "$0")/.."

read -rp "This will delete the DB data and the WCC domain. Continue? [y/N] " ans
case "${ans}" in
  y|Y|yes|YES) ;;
  *) echo "aborted"; exit 1 ;;
esac

docker compose down -v --remove-orphans
echo ">> Done. Run 'docker compose up -d' to bootstrap fresh."

#!/usr/bin/env bash
# Follow the most useful logs: AdminServer, UCM, and any init container that's
# still running. Pass a service name to follow just that one.
set -euo pipefail

cd "$(dirname "$0")/.."

if [[ $# -gt 0 ]]; then
  exec docker compose logs -f "$@"
fi
exec docker compose logs -f wcc-admin wcc-ucm

#!/usr/bin/env bash
# Creates the WCC WebLogic domain by invoking WLST with the bundled python
# script. Domain is written to a named volume so AdminServer + ManagedServers
# can share it.
set -euo pipefail

: "${DOMAIN_NAME:?missing}"
: "${DOMAIN_HOME:?missing}"
: "${ADMIN_USERNAME:?missing}"
: "${ADMIN_PASSWORD:?missing}"
: "${DB_CONNECTION_STRING:?missing}"
: "${RCU_PREFIX:?missing}"
: "${RCU_SCHEMA_PASSWORD:?missing}"

ORACLE_HOME="${ORACLE_HOME:-/u01/oracle}"
WLST="${ORACLE_HOME}/oracle_common/common/bin/wlst.sh"
[[ -x "${WLST}" ]] || { echo "WLST not found at ${WLST}"; exit 1; }

if [[ -d "${DOMAIN_HOME}" && -f "${DOMAIN_HOME}/startWebLogic.sh" ]]; then
  echo ">> Domain already exists at ${DOMAIN_HOME} — skipping creation."
  echo "   (delete the wcc-domain volume to force re-creation)"
  exit 0
fi

mkdir -p "$(dirname "${DOMAIN_HOME}")"

echo ">> Running WLST to create domain ${DOMAIN_NAME} at ${DOMAIN_HOME}"
"${WLST}" -skipWLSModuleScanning /opt/wcc/wlst/create-wcc-domain.py

echo ">> Domain created. Tree:"
ls -la "${DOMAIN_HOME}" | head -20

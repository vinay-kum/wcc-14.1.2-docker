#!/usr/bin/env bash
# Runs Oracle Repository Creation Utility (RCU) inside the WCC image to seed
# the WebCenter Content schemas into the database.
#
# Idempotency: this script DROPS any existing schemas with the same prefix
# before re-creating them. Safe to re-run, destructive on existing data.
#
# Required env (compose injects via .env):
#   DB_CONNECTION_STRING, DB_SYS_PASSWORD, RCU_PREFIX, RCU_SCHEMA_PASSWORD
set -euo pipefail

: "${DB_CONNECTION_STRING:?missing}"
: "${DB_SYS_PASSWORD:?missing}"
: "${RCU_PREFIX:?missing}"
: "${RCU_SCHEMA_PASSWORD:?missing}"

ORACLE_HOME="${ORACLE_HOME:-/u01/oracle}"
RCU="${ORACLE_HOME}/oracle_common/bin/rcu"
[[ -x "${RCU}" ]] || { echo "RCU not found at ${RCU}"; exit 1; }

PWD_FILE="$(mktemp)"
trap 'rm -f "${PWD_FILE}"' EXIT
{
  echo "${DB_SYS_PASSWORD}"
  echo "${RCU_SCHEMA_PASSWORD}"
} > "${PWD_FILE}"

echo ">> Dropping any pre-existing schemas with prefix ${RCU_PREFIX} (safe to fail on first run)"
"${RCU}" -silent -dropRepository \
  -databaseType ORACLE \
  -connectString "${DB_CONNECTION_STRING}" \
  -dbUser sys \
  -dbRole sysdba \
  -schemaPrefix "${RCU_PREFIX}" \
  -component CONTENT \
  -component MDS \
  -component STB \
  -component OPSS \
  -component IAU \
  -component IAU_APPEND \
  -component IAU_VIEWER \
  -component WLS \
  -f < "${PWD_FILE}" || echo "   (drop skipped — no existing schemas, continuing)"

echo ">> Creating RCU schemas with prefix ${RCU_PREFIX}"
"${RCU}" -silent -createRepository \
  -databaseType ORACLE \
  -connectString "${DB_CONNECTION_STRING}" \
  -dbUser sys \
  -dbRole sysdba \
  -useSamePasswordForAllSchemaUsers true \
  -selectDependentsForComponents true \
  -schemaPrefix "${RCU_PREFIX}" \
  -component CONTENT \
  -component MDS \
  -component STB \
  -component OPSS \
  -component IAU \
  -component IAU_APPEND \
  -component IAU_VIEWER \
  -component WLS \
  -tablespace USERS \
  -tempTablespace TEMP \
  -f < "${PWD_FILE}"

echo ">> RCU schemas created."

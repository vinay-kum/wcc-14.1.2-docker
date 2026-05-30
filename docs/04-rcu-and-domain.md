# 04 — RCU & domain creation

This page explains the two one-shot init containers: why they exist, what they
do, and how to debug them.

## Why two init containers?

WCC 14.1.2's image was designed to be operated by the WebLogic Kubernetes
Operator (WKO). WKO uses Kubernetes Jobs to do exactly two things before any
server starts:

1. **Seed the database** with Fusion Middleware schemas (RCU)
2. **Materialize a WebLogic domain** on a persistent volume

We replicate this with `wcc-rcu` and `wcc-domain-init`. Both use the WCC image
(which bundles RCU and WLST), run to completion, and exit. Compose's
`depends_on.condition: service_completed_successfully` enforces ordering.

## What `wcc-rcu` does

Source: [scripts/create-rcu-schemas.sh](../scripts/create-rcu-schemas.sh)

Runs `$ORACLE_HOME/oracle_common/bin/rcu -silent -createRepository` against
the DB. The `-component` flags select which schemas to create:

| Component | Schema created | Purpose |
|---|---|---|
| `CONTENT` | `<PREFIX>_OCS` | WCC core (Content Server) |
| `MDS` | `<PREFIX>_MDS` | Fusion Middleware metadata |
| `STB` | `<PREFIX>_STB` | Service Table (FMW discovery) |
| `OPSS` | `<PREFIX>_OPSS` | Platform security services |
| `IAU` / `IAU_APPEND` / `IAU_VIEWER` | `<PREFIX>_IAU*` | Audit services |
| `WLS` | `<PREFIX>_WLS*` | WebLogic-internal (`WLSRUNTIME`, `WLS`) |

The script `-dropRepository` first (best-effort) to make re-runs safe, then
`-createRepository`.

### Verifying RCU success

```bash
docker compose exec db sqlplus -L sys/${DB_SYS_PASSWORD}@FREEPDB1 as sysdba <<SQL
  SELECT username, account_status FROM dba_users WHERE username LIKE 'WCC1%';
SQL
```

You should see ~10 schemas, all `OPEN`. If they're `LOCKED`, that's normal —
RCU locks schemas and the domain creation step unlocks the ones it uses.

### Debugging `wcc-rcu`

```bash
docker compose logs wcc-rcu
# common failures:
#   ORA-12541: TNS:no listener      → DB not actually ready; retry after a minute
#   ORA-01017: invalid credentials  → DB_SYS_PASSWORD wrong in .env
#   RCU-6107: schemas already exist → dropRepository failed; manually drop or wipe oradata
```

## What `wcc-domain-init` does

Source: [scripts/create-domain.sh](../scripts/create-domain.sh) →
[config/wlst/create-wcc-domain.py](../config/wlst/create-wcc-domain.py)

Runs WLST in offline mode:
1. Reads the base WebLogic template (`wls.jar`)
2. Sets AdminServer port (7001) and admin user/password from env
3. Writes the base domain to `/u01/oracle/user_projects/domains/<DOMAIN_NAME>`
4. Re-opens the domain and adds two extension templates:
   - **JRF** (`oracle.jrf_template.jar`) — Fusion Middleware glue
   - **WCC** (`oracle.ucm.cs_template.jar`) — Content Server config
5. Creates the `UCM_server1` managed server on port 16200
6. Points each JDBC datasource at the matching RCU schema

The domain ends up on the `wcc-domain` named volume — shared with `wcc-admin`
and `wcc-ucm` at runtime.

### When template paths don't match

The WLST script encodes template paths based on Oracle's published 14.1.2
layout. If your image is structured differently, the WLST run fails with
`Template not found` or similar.

Find the actual templates inside the image:

```bash
# spin up a one-off shell in the WCC image
docker run --rm -it --platform linux/amd64 ${WCC_IMAGE} bash

# inside the container:
find /u01/oracle -name '*.jar' -path '*/templates/*' | head -40
find /u01/oracle -name 'wcc*' -o -name 'ucm*' 2>/dev/null
ls /u01/oracle/wccontent/common/templates/wls/ 2>/dev/null
```

Patch `BASE_TEMPLATE`, `JRF_TEMPLATE`, `WCC_TEMPLATE` in
[create-wcc-domain.py](../config/wlst/create-wcc-domain.py) with the real
paths, then `docker compose down -v && docker compose up -d` to re-bootstrap.

### When JDBC datasource names don't match

The `point_ds()` calls assume standard FMW + WCC datasource names. If the WCC
extension template names a datasource differently, those updates silently skip
(the script catches and logs). After first domain creation, list actual names:

```bash
docker compose exec wcc-admin ls /u01/oracle/user_projects/domains/${DOMAIN_NAME}/config/jdbc/
```

Then update the `(name, schema)` tuples in
[create-wcc-domain.py](../config/wlst/create-wcc-domain.py) accordingly.

## When to re-run init

If you change `RCU_PREFIX`, `DOMAIN_NAME`, or the WLST script:

```bash
./scripts/teardown.sh   # wipes oradata + wcc-domain volumes
docker compose up -d    # full re-bootstrap
```

If you only edit `create-wcc-domain.py` and want to keep the DB:

```bash
docker compose down
docker volume rm wcc14_wcc-domain
docker compose up -d
# the wcc-rcu init will re-run (and re-drop+create schemas), then domain-init
```

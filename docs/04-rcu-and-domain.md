# 04 — Bootstrap internals

This page documents what Oracle's bundled scripts do inside the WCC image.
You don't need to read this to use the stack — it's here for when something
goes wrong and you need to know what to inspect.

## The scripts live in the image

All bootstrap logic ships inside the WCC image at
`/u01/oracle/container-scripts/`. The most relevant entries:

| Script | Role |
|---|---|
| `createDomainandStartAdmin.sh` | Default CMD for `wcc-admin`. Orchestrates RCU + domain + AdminServer start. |
| `createWCCDomain.sh` | Called by the above. Runs RCU then invokes WLST. |
| `createWCContentDomain_PS4.py` | WLST script that builds the domain. |
| `startAdminContainer.sh` | Starts NodeManager + AdminServer and runs `setTopology.py`. |
| `setTopology.py` | Assigns machines/clusters to managed servers. |
| `configureOrStartWebCenterContent.sh` | CMD for `wcc-content`. Starts UCM_server1 + IBR_server1, runs first-time UCM/IBR autoconfig. |
| `startManagedServer.sh` / `stopManagedServer.sh` | Generic managed-server lifecycle helpers. |
| `keepContainerAlive.sh` | Tail-on-dummy-log used to keep the content container PID 1 alive. |
| `get_healthcheck_url.sh` | Generates the URL used by the image's default HEALTHCHECK (note: has a bug — we override the healthcheck in compose). |

## What `wcc-admin` does on first start

1. **Creates persistent dirs** under `/u01/oracle/user_projects/container-data/`
   (logs, RCU markers, env snapshot).
2. **Runs RCU** via `/u01/oracle/oracle_common/bin/rcu -silent -createRepository`
   against `${DB_CONNECTION_STRING}` with `-schemaPrefix ${DB_RCUPREFIX}` and
   components: `CONTENT MDS STB OPSS IAU IAU_APPEND IAU_VIEWER WLS`.
   - On success writes `container-data/RCU.${DB_RCUPREFIX}.suc`.
   - If `DB_DROP_AND_CREATE=true`, drops the prefix first.
3. **Runs WLST** with `createWCContentDomain_PS4.py` to build the domain
   at `/u01/oracle/user_projects/domains/${DOMAIN_NAME}`. The WLST extends
   the base WLS template with JRF + WCC templates and creates `AdminServer`,
   `UCM_server1`, and `IBR_server1` as managed servers.
   - On success writes `container-data/WCContent.Domain.Configure.suc`.
4. **Writes boot.properties** for AdminServer, UCM, IBR so they can start
   without prompting for credentials.
5. **Starts NodeManager** in the background, then AdminServer in the
   foreground via `startAdmin.sh`.
6. **Calls `setTopology.py`** to assign machines/clusters to the managed
   servers (this is what lets `wcc-content` start them remotely).

## What `wcc-content` does on first start

1. Validates the port env vars.
2. **First boot of UCM_server1** via `startManagedServer.sh UCM_server1`.
3. **Stops UCM_server1**, then templates `autoinstall.cfg.cs` and
   `ucm.properties` with the right host/port values, copies them into
   `${DOMAIN_HOME}/ucm/cs/bin/autoinstall.cfg`. This is the post-install
   auto-configuration Content Server expects on first boot.
4. **Restarts UCM_server1** with the autoinstall.cfg in place.
5. Repeats steps 2–4 for IBR_server1.
6. Calls `keepContainerAlive.sh` to keep PID 1 alive (tails a dummy log).

## Re-runs are idempotent

The `.suc` marker files in `container-data/` make re-runs cheap:

- If `RCU.${DB_RCUPREFIX}.suc` exists, RCU is skipped.
- If `WCContent.Domain.Configure.suc` exists, domain creation is skipped.

So `docker compose down && docker compose up -d` restarts servers without
re-bootstrapping — provided the `wcc-userprojects` volume still exists.

`docker compose down -v` (or `./scripts/teardown.sh`) wipes the volume,
which forces full re-bootstrap on next `up`. Set `DB_DROP_AND_CREATE=true`
in `.env` if you also need to drop+recreate schemas in a DB that survived.

## When something goes wrong

The marker files and logs in `container-data/` are your friends:

```bash
docker compose exec wcc-admin bash -lc '
  ls -la /u01/oracle/user_projects/container-data/
  ls -la /u01/oracle/user_projects/container-data/logs/
'
```

Typical files there:

- `RCU.WCC1.suc` (if RCU succeeded)
- `WCContent.Domain.Configure.suc` (if domain creation succeeded)
- `logs/RCU_createRepository.out` — RCU log
- `logs/UCM_server1_start-*.log` — UCM startup log
- `contenv.sh` — env snapshot from the first successful bootstrap

If domain creation failed mid-way, deleting these marker files and
restarting `wcc-admin` retries the step that failed.

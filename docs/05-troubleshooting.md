# 05 — Troubleshooting

## `unauthorized: authentication required` when pulling

You didn't accept the license for that image repo. Go to
<https://container-registry.oracle.com>, sign in, browse to the repo
(`database/free` or `middleware/webcenter-content_cpu`), click **Continue**
to accept terms. Then retry `docker pull`.

## `manifest unknown` when pulling WCC

The tag you put in `.env` is stale. Oracle rotates dated CPU tags. Refresh
from <https://container-registry.oracle.com/ords/ocr/ba/middleware/webcenter-content_cpu>
and update `WCC_IMAGE` in `.env`.

## DB healthcheck never goes healthy

First-run DB initialization takes 5–10 min on x86_64, 15+ min under arm64
emulation. Compose's `start_period: 180s` gives healthcheck retries a grace
window, but if it's been 20+ minutes:

```bash
docker compose logs db | tail -100
# look for stack traces or ORA- errors
```

Common causes:
- Not enough RAM (image needs ~2 GB just to start the listener)
- `oradata` volume on a filesystem that doesn't support fsync properly
  (some Docker Desktop configs on macOS)

## `wcc-rcu` exits with `ORA-12541: TNS:no listener`

The DB healthcheck went green prematurely — listener up but PDB still mounting.
Restart the init step:

```bash
docker compose up -d wcc-rcu
```

## `wcc-domain-init` fails with `Template not found`

The WLST template paths in [create-wcc-domain.py](../config/wlst/create-wcc-domain.py)
don't match your image's layout. See
[04-rcu-and-domain.md § When template paths don't match](04-rcu-and-domain.md#when-template-paths-dont-match).

## AdminServer starts but UCM never reaches RUNNING

Usually one of:

1. **Datasource lookup fails.** Check AdminConsole → Services → Data Sources.
   Test each datasource. If any fail, the schema name in
   [create-wcc-domain.py](../config/wlst/create-wcc-domain.py)
   doesn't match what RCU created, OR the password is wrong.

2. **UCM post-config wizard is waiting on you.** Hit <http://localhost:16200/cs>
   and complete the wizard.

3. **JVM heap too small.** UCM managed server defaults are tight for some
   workloads. Edit `$DOMAIN_HOME/bin/setUCMDomainEnv.sh` (or the equivalent)
   inside the running container, restart `wcc-ucm`.

## Slow bootstrap on Apple Silicon

Expected. WCC is linux/amd64-only and runs through Rosetta/qemu. To verify
emulation is happening:

```bash
docker compose exec wcc-admin uname -m
# x86_64    ← yes, that's emulated on arm64 host
```

Options:
- Accept it (one-time cost during bootstrap; runtime is OK after)
- Run on a Linux x86_64 VM (UTM with a UTM-supported x86 distro, or a cloud VM)

## Wipe and start over

```bash
./scripts/teardown.sh
docker compose up -d
```

## Inspect anything inside the running containers

```bash
docker compose exec wcc-admin bash
# inside:
#   $DOMAIN_HOME       — domain root
#   $ORACLE_HOME       — middleware install
#   /u01/oracle/shared — content vault (if you mounted it)
#   tail -f $DOMAIN_HOME/servers/AdminServer/logs/AdminServer.log
```

## Asking for help

If something fails in a way these docs don't cover, the most useful artifacts
to share:

```bash
docker compose ps -a > diag.txt
docker compose logs --tail=200 db wcc-rcu wcc-domain-init wcc-admin wcc-ucm >> diag.txt
docker compose exec wcc-admin ls /u01/oracle/user_projects/domains/${DOMAIN_NAME}/config/jdbc/ >> diag.txt 2>&1
```

# 05 — Troubleshooting

## `unauthorized: Auth failed` on `docker login`

You're using your SSO password instead of an Auth Token. Oracle retired SSO
password CLI auth on 2025-06-30. Generate an Auth Token from the registry
UI (your avatar → **Auth Token**) and use that as the docker password.
Username stays as your Oracle SSO email. Details in
[01-prerequisites.md](01-prerequisites.md#generate-an-auth-token-required-since-june-2025).

## `unauthorized: authentication required` on `docker pull`

License not accepted for that specific repo. Even with a working Auth Token,
each image repo (`database/free`, `middleware/webcenter-content`) requires
clicking **Continue** on its license page at
<https://container-registry.oracle.com> separately.

## `manifest unknown` on WCC pull

The tag pinned in `.env` was rotated. Refresh from
<https://container-registry.oracle.com/ords/ocr/ba/middleware/webcenter-content>
and update `WCC_IMAGE` in your local `.env`.

## DB healthcheck never goes healthy

First-run DB init takes 5–10 min on x86_64, 15+ min on arm64 emulation.
`start_period: 180s` gives the healthcheck grace, but if it's been 20+ min:

```bash
docker compose logs db | tail -100
```

Look for ORA- errors. Common causes: not enough RAM (DB needs ~2 GB just
to open the listener), or `oradata` on a filesystem that doesn't support
proper fsync.

## `wcc-admin` exits with RCU error

```bash
docker compose logs wcc-admin | grep -A5 -i "rcu\|ora-"
docker compose exec wcc-admin cat /u01/oracle/user_projects/container-data/logs/RCU_createRepository.out 2>/dev/null
```

Common cases:

- **`ORA-12541: TNS:no listener`** — DB healthcheck went green prematurely.
  `docker compose restart wcc-admin` after another minute.
- **`RCU-6107: schemas already exist`** — A previous run left schemas behind.
  Set `DB_DROP_AND_CREATE=true` in `.env` and restart `wcc-admin`.
- **`ORA-01017: invalid credentials`** — `DB_PASSWORD` in `.env` doesn't
  match what the DB was initialized with. If you changed `DB_PASSWORD`
  after first DB start, the DB still has the old password. Either change
  it back or `./scripts/teardown.sh` to wipe and start over.

## `wcc-admin` healthcheck never green but logs say `Server state changed to RUNNING`

The image's bundled healthcheck has a buggy URL template (`http://{$HOST:$PORT}/...`
with literal braces). Our compose file overrides with
`curl -sf http://localhost:7001/weblogic/ready`. If you removed that
override, that's the cause. Re-add it.

## `wcc-content` starts UCM but it never reaches RUNNING

Most common reasons:

1. **Datasource lookup fails.** Open AdminConsole → Services → Data Sources,
   click each one → Monitoring tab → Test. Any failing one needs its
   schema/password fixed.
2. **UCM autoinstall.cfg substitution went wrong.** Check inside the container:

   ```bash
   docker compose exec wcc-content cat /u01/oracle/user_projects/domains/${DOMAIN_NAME}/ucm/cs/bin/autoinstall.cfg
   ```

   Any `@PLACEHOLDER@` strings left un-substituted means
   `configureOrStartWebCenterContent.sh` couldn't see one of the port env
   vars. Verify all `UCM_*` / `IBR_*` env vars are set in `wcc-content`'s
   environment.
3. **Memory pressure.** UCM + IBR + AdminServer in two containers is
   ~6–8 GB. Bump Docker Desktop's resources.

## Slow bootstrap on Apple Silicon

Expected. WCC is linux/amd64-only and runs under Rosetta/qemu.

```bash
docker compose exec wcc-admin uname -m
# x86_64    ← emulated; native arm64 would say aarch64
```

Options: accept it (one-time cost; runtime is OK once servers are up), or
run on a Linux x86_64 VM (cloud instance, UTM, Multipass).

## Wipe and start over

```bash
./scripts/teardown.sh
docker compose up -d
```

## Inspect anything inside the running containers

```bash
docker compose exec wcc-admin bash
# inside:
#   /u01/oracle                          — ORACLE_HOME
#   /u01/oracle/user_projects/domains/$DOMAIN_NAME  — domain root
#   /u01/oracle/user_projects/container-data/       — bootstrap state + logs
#   /u01/oracle/container-scripts/       — Oracle's bundled scripts
```

## Asking for help

Useful artifacts to share:

```bash
docker compose ps -a > diag.txt
docker compose logs --tail=200 db wcc-admin wcc-content >> diag.txt
docker compose exec wcc-admin ls -la /u01/oracle/user_projects/container-data/ >> diag.txt 2>&1
docker compose exec wcc-admin cat /u01/oracle/user_projects/container-data/logs/RCU_createRepository.out >> diag.txt 2>&1
```

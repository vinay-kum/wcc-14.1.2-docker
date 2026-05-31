# 05 — Troubleshooting

## MS Office preview doesn't work (pptx/docx/xlsx show no rendition)

PDFs preview fine, but Office documents don't. This is **known-incomplete in
this playground** — the infrastructure is in place but the runtime config
isn't fully wired up.

**What's working** (post-bootstrap):

- UCM↔IBR outgoing provider `wcc_ibr` registered in
  `data/providers/providers.hda`
- `MSOfficeHtmlConverterSupport`, `DynamicConverter`, `TiffConverterSupport`,
  `XMLConverterSupport`, `InboundRefinerySupport` all Enabled
- IBR listening on intradoc port 5555 internally

**What's missing** (requires UI-driven admin work):

1. **File-format routing**. UCM currently sends Office files to the *local*
   `DynamicConverter` (which only knows HTML conversion, not PDF). You can
   verify this by querying `WCC1_OCS.HTMLCONVERSIONS` — Office uploads show
   `DOUTPUTFILESIZE=0`. UCM needs explicit rules saying "pptx/docx/xlsx →
   send to refinery `wcc_ibr`".
2. **IBR conversion settings**. IBR's accepted-file-format list needs Office
   types added via its admin UI (<http://localhost:16250/ibr> → Inbound
   Refinery → Conversion Settings).
3. **Configuration Manager**. The classic config tool is a Java desktop
   applet at `$DOMAIN_HOME/ucm/cs/bin/cm.sh`, requires X11 forwarding to use
   from a container.

**Why we stopped here**: end-to-end Office conversion configuration is
~4-6 hours of careful UI work that doesn't easily script. The playground
prioritizes a working stack + RedwoodUI + folder navigation + PDF
workflows over a fully-tuned conversion pipeline.

**If you want to finish it**: Oracle's official guide is *Managing Oracle
WebCenter Content* → chapter "Configuring Inbound Refinery". Plan for half
a day with the Configuration Manager and IBR admin UI open in parallel.

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

## RCU fails with "not certified" against DB 23.10+ / 26ai

Symptom in `wcc-admin` logs:

```text
ERROR - RCU-6080 Global prerequisite check failed for the specified database.
The selected Oracle Database instance is not certified with this version of
Oracle Fusion Middleware. Oracle Fusion Middleware 14c requires Oracle Database
23ai (23.4) or higher.
```

This is a **string-comparison bug in Oracle's RCU**, not a real cert issue.
The prereq query in `/u01/oracle/oracle_common/rcu/config/ComponentInfo.xml` does:

```sql
... AND version_full >= '23.0.0.0.0' AND version_full < '23.4.0.0.0'
```

In SQL string ordering, `'23.26.1.0.0' < '23.4.0.0.0'` is TRUE (because
`'2' < '4'` at character 3), so the check fires for every 23.10+ release
including 26ai. The check's INTENT is to block 23.0–23.3 only.

**This repo already includes a fix** — `image/Dockerfile.wcc` applies a
one-line sed to replace the buggy string comparison with a numeric one
using `TO_NUMBER(REGEXP_SUBSTR(...))`. `docker compose build` (run
automatically by `up`) produces a locally-tagged patched image.

If you're seeing this error, you likely either:

- pulled the base WCC image directly without going through compose-build, or
- removed/edited the `build:` block in `docker-compose.yml`

Run `docker compose build wcc-admin` then `docker compose up -d --force-recreate`
and check the image used:

```bash
docker compose ps --format "table {{.Service}}\t{{.Image}}"
# wcc-admin and wcc-content should both show the "...-patched" tag,
# NOT the raw container-registry.oracle.com path.
```

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

## UCM_server1 fails with `fcntl()` lock error on first bootstrap

Symptom in wcc-content logs:

```text
weblogic.management.DeploymentException: java.io.IOException: Error from
fcntl() for file locking, Resource temporarily unavailable, errno=11
...
Server state changed to FAILED.
A critical service failed. The server will shut itself down.
```

**Root cause** — a race in Oracle's bundled scripts on first bootstrap:

1. After domain creation, `startAdminContainer.sh` runs `setTopology.py`,
   which causes AdminServer to restart briefly.
2. In parallel, `configureOrStartWebCenterContent.sh` in `wcc-content` is
   running its first-boot sequence: start UCM, stop UCM via WLST (against
   AdminServer), copy `autoinstall.cfg`, restart UCM.
3. The stop-via-WLST hits AdminServer during its restart window →
   `Connection refused`.
4. Oracle's `stopManagedServer.sh` doesn't check exit code — it always
   prints "UCM_server1 stopped successfully" regardless. So the script
   proceeds.
5. UCM is still running, still holding its persistent-store file lock.
6. The next `startManagedServer.sh UCM_server1` tries to open the same
   lock file → `fcntl() errno=11` (EWOULDBLOCK) → critical service failure.

**Fix** — this repo's `docker-compose.yml` includes a `wait-for-admin-stable`
wrapper before `wcc-content` invokes Oracle's script. It requires 60
consecutive successful `/weblogic/ready` checks against `wcc-admin`
before kicking off the bootstrap, which gives the post-`setTopology`
restart enough time to finish.

If you removed the wrapper or hit this anyway:

```bash
# Confirm AdminServer is stable
curl -sf http://localhost:7001/weblogic/ready

# Force-recreate wcc-content (preserves all volumes; just restarts the script)
docker compose up -d --force-recreate wcc-content

# Watch for IBR_server1 to reach RUNNING — that's the actual end of bootstrap
docker compose logs -f wcc-content | grep --line-buffered "Server state changed to"
```

You may need to recreate 1–2 times on Apple Silicon because the emulated
fcntl semantics can leave a stale lock that needs a full container recycle
to clear.

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

## UCM_server1 mysteriously dies after IBR starts (OOM kill)

Symptom — `wcc-content` reports both servers started, but then UCM goes
unresponsive while IBR works fine. Inspecting UCM's start log shows:

```text
/.../startWebLogic.sh: line 226:  1425 Killed   ${JAVA_HOME}/bin/java ...
shutDownStatus=137
```

Exit 137 = SIGKILL from the Linux kernel's OOM killer. Total memory
across `db` + `wcc-admin` (AdminServer JVM) + `wcc-content` (UCM JVM +
IBR JVM) exceeds Docker Desktop's allocation and the kernel reclaims
whichever process the OOM scorer picks — usually UCM since it loads
last during the bootstrap chain.

**Fix** — increase Docker Desktop memory:

- macOS: whale icon → **Settings** → **Resources** → **Memory** slider →
  **at least 12 GB** → **Apply & Restart**
- Linux: edit `/etc/docker/daemon.json` and restart dockerd, OR don't worry
  about it (Linux Docker uses host RAM directly without a fixed cap)

After increasing memory, recreate the stack:

```bash
docker compose down            # keeps volumes — domain state preserved
docker compose up -d
```

Per-container RAM expectations (steady state, x86_64 emulated on arm64):

| Container | Expected RSS |
|---|---|
| `db` (Oracle 26ai Free) | 1.5–2.5 GB |
| `wcc-admin` (AdminServer JVM) | 2.0–2.5 GB |
| `wcc-content` (UCM + IBR JVMs) | 3.0–4.5 GB |
| **Total** | **6.5–9.5 GB** |

So 8 GB to Docker is borderline; 12 GB gives comfortable headroom.

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

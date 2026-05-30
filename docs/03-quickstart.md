# 03 — Quickstart

End-to-end first run on a fresh host. Reckon ~20 min on Linux x86_64, 45+ min
on Apple Silicon under emulation.

## 0. Prereqs

You've done [01-prerequisites.md](01-prerequisites.md):
- Oracle SSO + license acceptance for `database/free` and `middleware/webcenter-content_cpu`
- `docker login container-registry.oracle.com`
- 24 GB RAM, 60 GB disk free
- You've copied a current WCC image tag from the registry page

## 1. Configure

```bash
cp .env.example .env
```

Edit `.env`. The one value you MUST change:

```bash
WCC_IMAGE=container-registry.oracle.com/middleware/webcenter-content_cpu:14.1.2.0.0-<TAG>
#                                                                          ^^^^^
#                                                          replace with current dated tag
```

Optionally change passwords (defaults are intentionally weak — fine for
disposable playgrounds, not for anything else).

## 2. Pull images first (optional but useful)

Pulling separately surfaces auth / license problems before the bootstrap flow
starts and makes the first `up` faster to diagnose.

```bash
source .env  # so env vars are in shell
docker pull "${DB_IMAGE}"
docker pull "${WCC_IMAGE}"
```

If the WCC pull fails with `unauthorized`, you haven't accepted the
`webcenter-content_cpu` license at <https://container-registry.oracle.com>.

## 3. Bring it up

```bash
docker compose up -d
```

This kicks off the chain: `db` → `wcc-rcu` → `wcc-domain-init` → `wcc-admin` → `wcc-ucm`.

## 4. Watch the bootstrap

```bash
# everything at once (recommended for first run)
docker compose logs -f

# or one at a time
docker compose logs -f db          # wait for "DATABASE IS READY TO USE!"
docker compose logs -f wcc-rcu     # exits 0 when schemas are created
docker compose logs -f wcc-domain-init   # exits 0 when domain is written
docker compose logs -f wcc-admin   # wait for "Server state changed to RUNNING"
docker compose logs -f wcc-ucm     # wait for UCM_server1 "Server state changed to RUNNING"
```

Status of one-shot containers:

```bash
docker compose ps -a
# wcc-rcu and wcc-domain-init should show STATE=exited, EXITED=0
```

## 5. Access the UIs

| URL | Login |
|---|---|
| <http://localhost:7001/console> | `weblogic` / value of `ADMIN_PASSWORD` |
| <http://localhost:16200/cs> | `weblogic` / same |

On first hit, UCM (Content Server) shows a configuration wizard if the
post-config step didn't complete during domain creation — follow the prompts;
accept defaults. This is normal for a first-boot WCC instance.

## 6. Sanity-check the DB schemas

```bash
docker compose exec db sqlplus -L sys/${DB_SYS_PASSWORD}@FREEPDB1 as sysdba <<SQL
  SELECT username FROM dba_users WHERE username LIKE 'WCC1%' ORDER BY 1;
SQL
```

You should see `WCC1_OCS`, `WCC1_MDS`, `WCC1_STB`, `WCC1_OPSS`, `WCC1_IAU*`,
`WCC1_WLS*`.

## 7. Tear down

Keep volumes (faster restart, retains content and schemas):

```bash
docker compose down
```

Wipe everything (next `up` re-bootstraps from scratch):

```bash
./scripts/teardown.sh
```

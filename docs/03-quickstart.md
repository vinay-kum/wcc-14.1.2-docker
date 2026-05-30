# 03 — Quickstart

End-to-end first run on a fresh host. Plan for ~20–25 min on Linux x86_64,
~45–60 min on Apple Silicon under emulation.

## 0. Prereqs

You've done [01-prerequisites.md](01-prerequisites.md):

- Oracle SSO + license acceptance for `database/free` and `middleware/webcenter-content`
- Auth Token generated at `container-registry.oracle.com`
- `docker login container-registry.oracle.com` succeeds (using Auth Token, not SSO password)
- 24 GB RAM, 60 GB disk free

## 1. Configure

```bash
cp .env.example .env
```

`.env.example` ships with a known-working WCC tag and sensible defaults.
You don't need to edit anything for a basic playground run. Optionally change
the passwords (`DB_PASSWORD`, `DB_SCHEMA_PASSWORD`, `ADMIN_PASSWORD`).

## 2. Pull images first (recommended)

Pulling separately surfaces auth / license problems before the bootstrap
chain starts.

```bash
docker compose pull
```

If WCC fails with `unauthorized`, you haven't accepted the license for
`webcenter-content` in your browser at <https://container-registry.oracle.com>.

## 3. Bring it up

```bash
docker compose up -d
```

This chain runs:

- `db` starts; healthcheck waits for the PDB to be open
- `wcc-admin` starts; runs RCU against the DB, runs WLST to create the
  domain on the `wcc-userprojects` volume, starts AdminServer in the foreground
- `wcc-content` waits for `wcc-admin` to be healthy, then starts UCM_server1
  + IBR_server1 against the shared domain volume

## 4. Watch the bootstrap

```bash
# Everything at once (good for first run)
docker compose logs -f

# Or focused:
docker compose logs -f db          # wait for "DATABASE IS READY TO USE!"
docker compose logs -f wcc-admin   # wait for "Server state changed to RUNNING"
docker compose logs -f wcc-content # wait for UCM + IBR "RUNNING"

# Status of all services
docker compose ps
```

Notable progress markers in `wcc-admin` logs:

```text
WebCenter Content RCU Creation Phase   ← RCU starting
Repository Creation Utility - Create : Operation Completed   ← RCU done
Domain Configuration Phase             ← WLST starting
END Domain Configuration Phase         ← WLST done
Starting Node Manager                  ← server start
Server state changed to RUNNING        ← AdminServer ready
```

## 5. Access the UIs

| URL | Login |
|---|---|
| <http://localhost:7001/console> | `weblogic` / value of `ADMIN_PASSWORD` |
| <http://localhost:16200/cs> | same |
| <http://localhost:16250/ibr> | same |

On first hit, UCM (Content Server) may show a configuration wizard if
post-config didn't complete during domain creation — accept defaults.

## 6. Sanity-check the DB schemas

```bash
docker compose exec db sqlplus -L "sys/${DB_PASSWORD:-Welcome1_dbsys}@FREEPDB1 as sysdba" <<SQL
  SELECT username FROM dba_users WHERE username LIKE 'WCC1%' ORDER BY 1;
SQL
```

You should see ~10 schemas (`WCC1_OCS`, `WCC1_MDS`, `WCC1_STB`, `WCC1_OPSS`,
`WCC1_IAU*`, `WCC1_WLS*`).

## 7. Tear down

Keep volumes (faster restart, retains content + schemas):

```bash
docker compose down
```

Wipe everything (next `up` re-bootstraps from scratch):

```bash
./scripts/teardown.sh
```

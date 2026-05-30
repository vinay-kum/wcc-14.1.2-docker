# 02 — Architecture

## Container topology

```
                          ┌──────────────────────────┐
                          │  Docker network: wccnet  │
                          └──────────────────────────┘
                                       │
   ┌────────────────────┐    ┌─────────┴─────────┐    ┌────────────────────┐
   │ db (26ai Free)     │    │ wcc-admin         │    │ wcc-ucm            │
   │ 1521               │◄──►│ AdminServer 7001  │◄──►│ UCM_server1 16200  │
   │ vol: oradata       │    │ vol: wcc-domain   │    │ vol: wcc-domain    │
   │      /opt/oracle/  │    │      wcc-shared   │    │      wcc-shared    │
   │      oradata       │    │ /u01/oracle/      │    │ /u01/oracle/       │
   └────────────────────┘    │   user_projects   │    │   user_projects    │
            ▲                └───────────────────┘    └────────────────────┘
            │                          ▲
            │                          │ (run-once, exits 0)
   ┌────────┴──────────┐    ┌─────────┴─────────┐
   │ wcc-rcu (init)    │───►│ wcc-domain-init   │
   │ Runs RCU to       │    │ Runs WLST to      │
   │ create schemas    │    │ build domain on   │
   │ in DB             │    │ wcc-domain volume │
   └───────────────────┘    └───────────────────┘
```

## Bootstrap order

Compose enforces this with `depends_on.condition`:

1. `db` starts and runs its healthcheck until DB is open
2. `wcc-rcu` runs once, calls `rcu -createRepository` against the DB, exits 0
3. `wcc-domain-init` runs once, calls WLST to create the WCC domain on the
   `wcc-domain` named volume, exits 0
4. `wcc-admin` starts AdminServer with that domain mounted; healthcheck on
   `/weblogic/ready`
5. `wcc-ucm` waits for AdminServer to be healthy, then starts UCM_server1
   pointing at `t3://wcc-admin:7001`

Re-runs: if the `wcc-domain` volume already has a populated domain,
`create-domain.sh` short-circuits and skips re-creation. The RCU step is
destructive — it drops the prior schemas before re-creating — so don't expect
to preserve content if you tear down and recreate.

## Volumes

| Volume | Mount in container | Purpose | Lifetime |
|---|---|---|---|
| `oradata` | `/opt/oracle/oradata` (db) | DB datafiles | persistent across `up`/`down`; wiped by `down -v` |
| `wcc-domain` | `/u01/oracle/user_projects` (wcc-*) | WebLogic domain home | persistent; wiped by `down -v` |
| `wcc-shared` | `/u01/oracle/shared` (wcc-admin, wcc-ucm) | content vault/web/native files | persistent; wiped by `down -v` |

## Networks

Single bridge network `wccnet`. All inter-container references use service
names (`db`, `wcc-admin`, etc.) as DNS.

## Ports (host:container)

| Host | Container | Service | Purpose |
|---|---|---|---|
| 1521 | 1521 | db | Oracle listener (SQL Developer, sqlcl, app connections) |
| 7001 | 7001 | wcc-admin | WebLogic AdminConsole (`/console`) |
| 16200 | 16200 | wcc-ucm | Content Server UI (`/cs`) |
| 4444 | 4444 | wcc-ucm | UCM Intradoc (internal protocol) |

You can change host-side ports in `.env` without touching `docker-compose.yml`.

## What's NOT included (yet)

- IBR (Inbound Refinery) — needs a second managed server + matching JVM args
- IPM / Capture / WCC ADF UI — additional managed servers
- TLS for AdminConsole / UCM — runs HTTP on a private bridge network
- NodeManager — domain runs in foreground mode via `startWebLogic.sh`,
  fine for dev but you'd want NM for production-like restarts
- Backup / restore — `oradata` and `wcc-domain` volumes are not snapshotted

These are deliberate scope cuts to keep the playground reproducible. Pull
requests welcome.

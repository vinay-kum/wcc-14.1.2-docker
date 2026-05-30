# 02 — Architecture

## Container topology

```text
                       ┌──────────────────────────┐
                       │  Docker network: wccnet  │
                       └──────────────────────────┘
                                    │
   ┌────────────────────┐   ┌──────┴──────────┐   ┌─────────────────────┐
   │ db (26ai Free)     │   │ wcc-admin       │   │ wcc-content         │
   │ :1521              │◄─►│ AdminServer     │◄─►│ UCM_server1 :16200  │
   │ vol: oradata       │   │ :7001           │   │ IBR_server1 :16250  │
   │  /opt/oracle/      │   │ vol:            │   │ vol:                │
   │  oradata           │   │  wcc-userprojects│  │  wcc-userprojects   │
   └────────────────────┘   │  /u01/oracle/   │   │  (shared with admin)│
                            │  user_projects  │   └─────────────────────┘
                            └─────────────────┘
```

## Image build

On `docker compose up`, compose first builds a thin layered image from
[`image/Dockerfile.wcc`](../../image/Dockerfile.wcc). The layer applies a
single sed patch to fix Oracle's RCU string-comparison bug against DB 23.10+
(including 26ai). The resulting locally-tagged image is what `wcc-admin`
and `wcc-content` actually run. See
[05-troubleshooting.md](05-troubleshooting.md#rcu-fails-with-not-certified-against-db-2310--26ai)
for the bug background.

## Bootstrap order

Compose enforces ordering via `depends_on.condition`:

1. `db` starts and runs its healthcheck until the listener and PDB are open.
2. `wcc-admin` starts. Its default CMD is Oracle's
   `createDomainandStartAdmin.sh`, which on first start:
   - runs RCU (`rcu -createRepository`) against the DB to create the
     WCC schemas (CONTENT, MDS, STB, OPSS, IAU*, WLS)
   - runs WLST (`createWCContentDomain_PS4.py`) to build the domain at
     `/u01/oracle/user_projects/domains/${DOMAIN_NAME}`
   - starts NodeManager + AdminServer in the foreground
   On subsequent starts, the script detects the `RCU.<prefix>.suc` and
   `WCContent.Domain.Configure.suc` marker files and skips RCU + domain
   creation, only restarting servers.
3. `wcc-content` waits for `wcc-admin` to be healthy, then runs Oracle's
   `configureOrStartWebCenterContent.sh` which starts UCM_server1 and
   IBR_server1 against the shared domain volume.

## Volumes

| Volume | Mount in container | Purpose | Lifetime |
|---|---|---|---|
| `oradata` | `/opt/oracle/oradata` (db) | DB datafiles | persists across `up`/`down`; wiped by `down -v` |
| `wcc-userprojects` | `/u01/oracle/user_projects` (wcc-admin + wcc-content) | WebLogic domain + Oracle's `container-data` marker dir | persists; wiped by `down -v` |

The wcc-userprojects volume holds:

- `domains/wcc_domain/` — full WebLogic domain (config.xml, servers, security, etc.)
- `container-data/` — Oracle's bootstrap state (RCU success markers, env snapshot, logs)

## Networks

Single bridge network `wccnet`. All inter-container references use service
names as DNS — `wcc-content` reaches the admin server at `t3://wcc-admin:7001`.

## Ports (host:container)

| Host | Container | Service | Purpose |
|---|---|---|---|
| 1521 | 1521 | db | Oracle listener |
| 7001 | 7001 | wcc-admin | WebLogic AdminConsole (`/console`) |
| 16200 | 16200 | wcc-content | UCM Content Server UI (`/cs`) |
| 16250 | 16250 | wcc-content | IBR (Inbound Refinery) UI |
| 4444 | 4444 | wcc-content | UCM Intradoc protocol |
| 5555 | 5555 | wcc-content | IBR Intradoc protocol |

You can remap host-side ports in `.env` (`UCM_PORT`, `IBR_PORT`, etc.) without
editing `docker-compose.yml`.

## What's NOT included

- **IPM / Capture / WCC ADF UI** — Oracle's image supports extending the
  domain with these by setting the `component` env var on `wcc-admin` to e.g.
  `"IPM,CAPTURE,ADFUI"`. Each adds its own managed server and needs an
  additional companion container running the matching
  `configureOrStartIPM.sh` / `configureOrStartCapture.sh` / `configureOrStartWCCADF.sh`.
- **TLS** — runs HTTP on a private bridge network. Add a reverse proxy
  (nginx/traefik) in front for TLS.
- **Backup / restore** — `oradata` and `wcc-userprojects` are not snapshotted.

These are deliberate scope cuts to keep the playground reproducible.

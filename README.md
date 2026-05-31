# Oracle WebCenter Content 14.1.2 + Oracle AI Database 26ai — Docker Playground

A docker-compose orchestration that brings up Oracle WebCenter Content 14.1.2
backed by Oracle AI Database 26ai Free. Built for local prototyping, demos,
and learning the WCC + WebLogic stack without standing up Kubernetes.

The WCC 14.1.2 image is **self-bootstrapping** — Oracle bundles scripts
inside the image (`/u01/oracle/container-scripts/`) that handle RCU schema
creation, WLST domain creation, and server startup. This compose just wires
up two containers using those scripts and connects them to the database.

> **Two image-layer patches applied:**
>
> 1. **RCU SQL comparison fix** — Oracle's RCU has a string-comparison bug
>    that mis-rejects DB 23.10+ (including 26ai = 23.26) as "uncertified".
>    A one-line sed in [`image/Dockerfile.wcc`](image/Dockerfile.wcc)
>    replaces the broken query with a numeric one.
> 2. **WCC Bundle Patch 39129716 (March 2026)** — adds the `RedwoodUI`
>    server component (introduced in April 2025 bundle, not present in the
>    base Dec 2024 container image). Drop the patch zip into
>    `image/patches/` and the Dockerfile applies it via OPatch.
>    See [`image/patches/README.md`](image/patches/README.md) for the MOS
>    download instructions.

## What you get

```text
┌────────────────────────────────────────────────────────────┐
│ docker-compose                                              │
│                                                             │
│   db ──────► wcc-admin ─────────► wcc-content              │
│   (26ai)     (AdminServer)        (UCM_server1 +           │
│              :7001                  IBR_server1)            │
│                                    :16200, :16250          │
└────────────────────────────────────────────────────────────┘
```

| Service | Image | Lifecycle | Host port |
|---|---|---|---|
| `db` | `container-registry.oracle.com/database/free` | long-running | 1521 |
| `wcc-admin` | WCC 14.1.2 | long-running (creates domain on first start) | 7001 |
| `wcc-content` | WCC 14.1.2 | long-running (UCM + IBR) | 16200, 16250, 4444, 5555 |

## Quick start

```bash
# 1. One-time: accept Oracle licenses at
#    https://container-registry.oracle.com (database/free + middleware/webcenter-content)
#    Generate an Auth Token from your profile menu (SSO password no longer works).
docker login container-registry.oracle.com

# 2. Configure
cp .env.example .env
# Defaults work for a playground. Optionally change passwords.

# 3. Pull images (~10 GB total)
docker compose pull

# 4. Bring up
docker compose up -d

# 5. Watch the bootstrap (first run is 15–25 min on x86_64, 45+ min on arm64)
docker compose logs -f wcc-admin
# wait for: "Server state changed to RUNNING" (AdminServer)
docker compose logs -f wcc-content
# wait for: UCM_server1 RUNNING, then IBR_server1 RUNNING

# 6. Once healthy:
#    AdminConsole:  http://localhost:7001/console     (weblogic / Welcome1_wls)
#    Content UI:    http://localhost:16200/cs
```

Full walkthrough in [docs/03-quickstart.md](docs/03-quickstart.md).

## Documentation

- [01 — Prerequisites](docs/01-prerequisites.md): Oracle SSO, Auth Token, license acceptance, host requirements
- [02 — Architecture](docs/02-architecture.md): container topology, volumes, networks, ports
- [03 — Quickstart](docs/03-quickstart.md): end-to-end first-run walkthrough
- [04 — Bootstrap internals](docs/04-rcu-and-domain.md): what Oracle's bundled scripts do
- [05 — Troubleshooting](docs/05-troubleshooting.md): common failures
- [06 — Publishing](docs/06-publishing.md): what you can and can't publish under Oracle's license

## What works (and what doesn't)

| Capability | Status | Notes |
|---|---|---|
| DB 26ai + WCC 14.1.2 stack up + healthy | ✅ | RCU + domain creation auto-bootstrap |
| WebLogic AdminConsole | ✅ | <http://localhost:7001/console> |
| Content Server classic UI | ✅ | <http://localhost:16200/cs> |
| Redwood UI | ✅ | <http://localhost:16200/cs/idcplg?IdcService=REDWOODUI> (needs Mar 2026 bundle patch — see `image/patches/`) |
| Folder browsing (FrameworkFolders) | ✅ | Enabled at runtime via post-bootstrap script |
| PDF preview in Redwood UI | ✅ | Works directly — PDFs are already web-viewable |
| **MS Office (pptx/docx/xlsx) preview** | ⚠️ **Incomplete** | UCM↔IBR provider is registered and components are enabled, but file-format routing (sending Office types to IBR) isn't configured. UCM falls back to local DynamicConverter which produces zero-byte output for Office formats. See [docs/05-troubleshooting.md#ms-office-conversion](docs/05-troubleshooting.md) for what's needed to finish. |
| Image search, check-in/out, metadata | ✅ | Standard WCC functionality |

## Honest caveats

- **You can't publish the resulting image publicly.** Oracle's license forbids
  redistributing their middleware images (including patched derivatives).
  Publish this *orchestration repo* instead — users pull the official Oracle
  image and download patches from MOS themselves.
- **Apple Silicon (arm64) hosts run WCC under emulation.** Oracle middleware
  images are linux/amd64 only. Expect 3–5× slower startup, 12 GB+ memory
  needed in Docker Desktop. The DB has an ARM-native tag but WCC does not.
- **Image tags rotate.** `.env.example` pins a known-working base tag
  (`14.1.2.0-jdk21-ol9-241205`); refresh from the registry page if it goes
  stale.
- **The bundle patch is gitignored** — you download it from MOS yourself
  (Doc ID 2479547.1 lists all WCC bundles). Drop the zip into
  `image/patches/` before `docker compose build`.
- **MS Office → PDF conversion needs UI-driven admin work** that we don't
  automate. The infrastructure is in place; finishing it requires
  Configuration Manager (Java applet) clicks. Considered out of scope for a
  playground.

## License

MIT for the contents of this repo (orchestration only). Oracle products
remain under their respective Oracle licenses. See [LICENSE](LICENSE).

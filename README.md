# Oracle WebCenter Content 14.1.2 + Oracle AI Database 26ai — Docker Playground

A docker-compose orchestration that brings up Oracle WebCenter Content 14.1.2
backed by Oracle AI Database 26ai Free. Built for local prototyping, demos, and
learning the WCC + WebLogic stack without standing up Kubernetes.

> **Status:** Working scaffold. The compose file and init flow are based on Oracle's
> published 14.1.2 docs and the `fmw-kubernetes` reference. The exact WCC image
> tag, WLST template paths, and JDBC datasource names need to be verified
> against the image you actually pull — see [docs/05-troubleshooting.md](docs/05-troubleshooting.md).

## What you get

```text
┌──────────────────────────────────────────────────────────────────┐
│ docker-compose                                                    │
│                                                                   │
│   db ────────► wcc-rcu ────► wcc-domain-init ────► wcc-admin ─┐  │
│   (26ai)       (one-shot)    (one-shot, WLST)     (7001)      │  │
│                                                                │  │
│                                              wcc-ucm ◄────────┘  │
│                                              (16200)              │
└──────────────────────────────────────────────────────────────────┘
```

| Service | Image | Lifecycle | Host port |
|---|---|---|---|
| `db` | `container-registry.oracle.com/database/free` | long-running | 1521 |
| `wcc-rcu` | WCC 14.1.2 CPU | one-shot init | — |
| `wcc-domain-init` | WCC 14.1.2 CPU | one-shot init | — |
| `wcc-admin` | WCC 14.1.2 CPU | long-running | 7001 |
| `wcc-ucm` | WCC 14.1.2 CPU | long-running | 16200, 4444 |

## Quick start

```bash
# 1. One-time: accept Oracle license terms at
#    https://container-registry.oracle.com (database/free + middleware/webcenter-content_cpu)
docker login container-registry.oracle.com

# 2. Configure
cp .env.example .env
$EDITOR .env   # set WCC_IMAGE to the dated tag from Oracle Container Registry

# 3. Bring up (first run takes 10–25 min on Linux x86_64, longer under emulation)
docker compose up -d

# 4. Follow what's happening
./scripts/tail-logs.sh

# 5. Once wcc-ucm is healthy, open:
#    AdminConsole:  http://localhost:7001/console     (weblogic / Welcome1_wls)
#    Content UI:    http://localhost:16200/cs
```

Full walkthrough in [docs/03-quickstart.md](docs/03-quickstart.md).

## Documentation

- [01 — Prerequisites](docs/01-prerequisites.md): Oracle SSO, license acceptance, host requirements
- [02 — Architecture](docs/02-architecture.md): container topology, volumes, networks, ports, lifecycle
- [03 — Quickstart](docs/03-quickstart.md): end-to-end first-run walkthrough
- [04 — RCU & domain creation](docs/04-rcu-and-domain.md): what the init containers do and why
- [05 — Troubleshooting](docs/05-troubleshooting.md): common failures, verifying image internals
- [06 — Publishing](docs/06-publishing.md): what you can and can't publish under Oracle's license

## Honest caveats

- **WCC 14.1.2 has no public Dockerfile.** Oracle only publishes Dockerfile source
  for WCC 12.2.1.4. For 14.1.2, you pull a pre-built image from
  `container-registry.oracle.com`. This repo orchestrates that image — it doesn't
  rebuild it.
- **The 14.1.2 image is K8s-shaped.** Oracle ships it expecting the WebLogic
  Kubernetes Operator to handle domain bootstrap. We replicate that flow with
  one-shot init containers, but the runtime contract isn't fully public, so
  template paths and JDBC datasource names may need adjustment. See
  [docs/05-troubleshooting.md](docs/05-troubleshooting.md).
- **You can't publish the resulting image publicly.** Oracle's license forbids
  redistributing their middleware images. Publish this *orchestration repo*
  instead — users pull the official Oracle image themselves.
- **Apple Silicon (arm64) hosts run WCC under emulation.** Oracle middleware
  images are linux/amd64 only. Expect 3–5× slower startup. The DB has an
  ARM-native tag but WCC does not.

## License

MIT for the contents of this repo (orchestration only). Oracle products remain
under their respective Oracle licenses. See [LICENSE](LICENSE).

# 01 — Prerequisites

## Host

| Requirement | Recommended | Minimum |
|---|---|---|
| OS | Linux x86_64 (RHEL/OL 8/9, Ubuntu 22.04+) | macOS / Windows with Docker Desktop |
| CPU | 8 cores | 4 cores |
| RAM | 24 GB | 16 GB (tight — DB + AdminServer + UCM all run JVMs) |
| Disk | 60 GB free | 40 GB |
| Docker | Engine 24+ with Compose v2.20+ | v2.13+ (for `service_completed_successfully`) |

### Apple Silicon (arm64) note

Oracle's WebCenter Content image is linux/amd64 only. On M-series Macs, Docker
Desktop runs it under Rosetta/qemu emulation. Expect:

- ~3–5× slower domain bootstrap (first `docker compose up` may take 45+ minutes)
- Significantly higher CPU usage during startup
- Some flaky JVM behavior under heavy concurrent load

The Oracle Database Free image *does* have an ARM-native tag if you prefer
faster DB startup — see the registry page.

For serious local work, a Linux x86_64 VM (UTM, Multipass, cloud instance) is
much smoother than emulation.

## Oracle Container Registry access

You need an Oracle SSO account with license acceptance for two image
repositories. This is **free** but **manual** (one-time, per SSO account):

1. Go to <https://container-registry.oracle.com>
2. Sign in with Oracle SSO
3. Browse to **Database** → **free** → click **Continue** to accept terms
4. Browse to **Middleware** → **webcenter-content_cpu** → click **Continue**

### Generate an Auth Token (required since June 2025)

Oracle retired SSO password support for `docker login` on June 30, 2025.
You now need an Auth Token generated from inside the registry UI. You do
**not** need an OCI tenancy for this — the token lives on
`container-registry.oracle.com` itself.

1. While signed in at <https://container-registry.oracle.com>, click your
   user name/avatar in the top right
2. Select **Auth Token** from the dropdown
3. Generate a token and copy it (long opaque string — store it in your
   password manager; you can't view it again later)
4. Now log in from the CLI:

   ```bash
   docker login container-registry.oracle.com
   # Username: <your Oracle SSO email, e.g. you@example.com>
   # Password: <paste the Auth Token, NOT your SSO password>
   ```

If you paste your SSO password you'll get `unauthorized: Auth failed`,
even though the same credentials work in the browser. The browser uses
SAML/federated SSO; the CLI endpoint only accepts basic auth with the
token.

### Per-repo license acceptance

Even with a valid Auth Token, `docker pull` returns
`unauthorized: authentication required` until you've clicked **Continue**
on the license page for *each* image repo (Database/free AND
Middleware/webcenter-content_cpu — two separate clicks).

## Find the current image tags

The `latest` tag is fine for the DB but **not** for WCC (Oracle publishes dated
CPU tags and rotates them). Pin a specific tag in `.env`.

- DB: <https://container-registry.oracle.com/ords/ocr/ba/database/free>
- WCC: <https://container-registry.oracle.com/ords/ocr/ba/middleware/webcenter-content_cpu>

Copy the tag from the registry page (e.g. `14.1.2.0.0-jdk17-ol8-260115`) into
`.env` as `WCC_IMAGE=container-registry.oracle.com/middleware/webcenter-content_cpu:<tag>`.

## Local tools (optional but useful)

- `sqlplus` or `sqlcl` for poking the DB from the host
- `wlst` is inside the container — no need to install locally
- `curl` for hitting health endpoints

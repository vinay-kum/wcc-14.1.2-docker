# 06 — Publishing

## What you CAN publish

- This repo: docker-compose.yml, scripts, WLST, docs, GitHub Actions
- Your customizations, configuration templates, integration code
- Test fixtures (as long as they don't contain Oracle binaries or
  password-protected installers)

These contain zero Oracle code. MIT works fine.

## What you CANNOT publish

Per Oracle Master Software License Agreement and OTN Standard Terms:

- The Oracle WebCenter Content image (or any rebuild of it) on a public
  registry like Docker Hub or GHCR
- The FMW Infrastructure image
- Oracle Database images
- Any Oracle binary (`.jar`, `.zip`, `.bin`) from edelivery.oracle.com
- Domain backups containing Oracle JARs

Even pushing a layered/derived image to a **private** registry is fine for
your own use, but you can't make it publicly pullable.

If you want others to use your playground, they pull the official Oracle
image from `container-registry.oracle.com` themselves after accepting the
license — that's exactly the flow this repo encodes.

## Publishing this repo to GitHub

```bash
# from /Users/vinay/instance/wcc
git add .
git commit -m "Initial WCC 14.1.2 + DB 26ai playground"
gh repo create wcc14-playground --public --source=. --push
```

(Adjust `--public` to `--private` if you'd rather keep it under wraps until
you've smoke-tested.)

## CI in this repo

[.github/workflows/ci.yml](../.github/workflows/ci.yml) does:

- `docker compose config` (catches YAML / env interpolation errors)
- `shellcheck` on scripts/
- Markdown lint on docs/

It does **not** attempt to pull Oracle images or stand up the stack — that
requires Oracle SSO credentials, which don't belong in CI secrets unless you
have explicit authorization.

## Building a private layered image (advanced)

If you want a single-image experience for your own team (private registry):

```dockerfile
# Dockerfile.private — DO NOT push publicly
FROM container-registry.oracle.com/middleware/webcenter-content:14.1.2.0-jdk21-ol9-241205
# Oracle's bundled bootstrap scripts already live in /u01/oracle/container-scripts/.
# Bake in only what you need to override — for example a custom autoinstall.cfg.cs
# or a wrapper around configureOrStartWebCenterContent.sh.
COPY overrides/autoinstall.cfg.cs /u01/oracle/container-scripts/autoinstall.cfg.cs
```

Push to a private registry (your org's Artifactory, ECR, GAR, ACR — all fine).
Don't push to a public registry.

## Trademark

"Oracle", "WebCenter", "WebLogic" are Oracle trademarks. If you publish this
under a non-Oracle GitHub user/org, prefix your repo name to make it clear
it's unofficial. E.g. `vkumar/wcc14-playground` is fine;
`oracle-wcc/playground` is not.

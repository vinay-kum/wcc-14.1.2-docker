# `image/` — local layered WCC image

This directory builds a thin layered image on top of Oracle's official
WCC 14.1.2 image to work around a string-comparison bug in Oracle's
RCU prereq check that prevents DB 23.10+ (including 26ai = 23.26) from
being recognized as ≥ 23.4.

See [Dockerfile.wcc](Dockerfile.wcc) for the full explanation of what's
patched and why. The patch is one sed substitution against a single SQL
query in `/u01/oracle/oracle_common/rcu/config/ComponentInfo.xml`.

`docker compose build` (run automatically by `docker compose up`) produces
a locally-tagged image named `${WCC_IMAGE}` from `.env`.

**Do not push the layered image to a public registry.** Oracle's license
forbids redistributing their middleware images, even with modifications.
Private registries (your org's Artifactory, ECR, GAR, ACR) are fine.

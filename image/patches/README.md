# Oracle patch drop zone

Place Oracle bundle-patch / one-off zip files downloaded from
[My Oracle Support](https://support.oracle.com) here. They are
**license-restricted** and **must never be committed** — the root `.gitignore`
excludes `*.zip`, `*.jar`, `*.bin` globally.

## What goes here

For WCC 14.1.2 RedwoodUI support, you typically need the latest **WebCenter
Content Bundle Patch** for `14.1.2.0.0`:

- File pattern: `p<patch_id>_141200_Linux-x86-64.zip`
- Examples (illustrative, replace with actual numbers from MOS):
  - April 2025 bundle — first patch shipping `RedwoodUI` component
  - July 2025 bundle — adds Redwood Outlook integration
  - January 2026 bundle — Elasticsearch 8.x + Redwood enhancements (newest)

You may also need a newer OPatch if the bundle's readme requires it:

- File pattern: `p28186730_<version>_Linux-x86-64.zip` (OPatch 13.9.4.x updater)

## How patches are applied

`image/Dockerfile.wcc` has a stage that:

1. Copies any `.zip` from `image/patches/` into the layered image
2. Verifies OPatch version against the bundle's prereq
3. Runs `$ORACLE_HOME/OPatch/opatch apply` for each patch
4. Cleans up the zips from the final image layer

On `docker compose build`, the patches are baked into the local
`wcc14-playground/wcc:*` tag. Rebuild after dropping a new patch:

```bash
docker compose build wcc-admin
docker compose down              # optional: also -v to wipe domain for a clean component install
docker compose up -d
```

After UCM_server1 restarts, open Component Manager and verify `RedwoodUI`
is present and enabled. Access at:

```
http://localhost:16200/cs/idcplg?IdcService=REDWOODUI
```

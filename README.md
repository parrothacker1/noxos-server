# noxos-server

Static OTA manifest publisher for NoxOS. No running service — a scheduled GitHub Action rebuilds a static manifest tree from [noxos-os](https://github.com/parrothacker1/noxos-os)'s GitHub Releases and publishes it to GitHub Pages.

## Why no server

The OTA artifacts already live on GitHub Releases (versioned, free, well understood). Once you have that, an "update check" is just "read a small JSON file" — that doesn't need a live server, a database, or a cloud function. It needs a file that gets regenerated when a release ships.

## How it works

1. `.github/workflows/publish-manifest.yml` runs on a schedule (every 6h) and on manual dispatch.
2. `scripts/fetch-releases.sh` pulls every release + asset from `noxos-os` via the GitHub API.
3. `scripts/build-manifest.sh` parses each `.zip` asset's filename (`noxos-<version>-<YYYYMMDD>-<channel>-<device>.zip`), groups builds by device/channel, and writes `docs/<device>/<channel>.json` — sorted newest-first, one file per device+channel, no per-request filtering needed.
4. `docs/` gets published to GitHub Pages.
5. The client (`noxos-app`) fetches `https://parrothacker1.is-a.dev/noxos-server/<device>/<channel>.json` (custom domain configured on this GitHub account's Pages sites — not the default `github.io` URL), compares its own `incremental` against the list, and picks what to download itself — no server-side version-diffing logic.

Manifest entry shape:

```json
{"device":"sunfish","type":"nightly","incremental":"v1.2.0","filename":"noxos-1.2-20260301-nightly-sunfish.zip",
 "timestamp":1772323200,"size":900000000,"sha256":"...","version":"1.2","url":"https://github.com/.../noxos-1.2-....zip",
 "changelog":"release notes body"}
```

`sha256` comes from an optional `<filename>.sha256` sidecar asset uploaded alongside the zip; if absent, it's `null` rather than downloading and hashing multi-GB images in CI.

## Deliberately not built

- **No patch chaining.** A device more than one version behind downloads the latest full image, not a sequence of incrementals. Real ROM projects (LineageOS, GrapheneOS) avoid N-hop delta chains for the same reason: one failed hop mid-chain breaks the update, and pre-building deltas for every version pair doesn't scale.
- **No push notifications.** The client polls on a schedule. Push would mean either Firebase Cloud Messaging (conflicts with being GMS-independent) or a self-hosted UnifiedPush relay (real infra this project doesn't need yet).

## Local testing

```sh
./scripts/test-build-manifest.sh   # transform logic against testdata/releases.json, no network needed
./scripts/generate-manifest.sh     # full pipeline against the real noxos-os repo, needs `gh` auth
```

Part of [NoxOS](https://github.com/parrothacker1/noxos). Status: manifest generator built and tested against a fixture; unverified against real `noxos-os` releases since none exist yet (Phase 1 hasn't produced a build).

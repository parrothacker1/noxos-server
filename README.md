<div align="center">

<img src="https://raw.githubusercontent.com/parrothacker1/noxos/main/assets/branding/logo-mark.svg" width="80" height="80" alt="NoxOS Logo">

# noxos-server

**Serverless OTA update manifest publisher for NoxOS**

![Bash](https://img.shields.io/badge/Bash-5.x-4EAA25?style=flat-square&logo=gnubash&logoColor=white)
![jq](https://img.shields.io/badge/jq-1.6-informational?style=flat-square)
![GitHub Actions](https://img.shields.io/badge/GitHub%20Actions-scheduled-2088FF?style=flat-square&logo=githubactions&logoColor=white)
![Pages](https://img.shields.io/badge/GitHub%20Pages-live-222?style=flat-square&logo=github&logoColor=white)
![Uptime](https://img.shields.io/badge/Uptime-100%25%20(static%20file)-4FD1C5?style=flat-square)

</div>

---

## Overview

`noxos-server` generates and publishes the OTA update manifests that `noxos-app` clients query to discover new ROM releases and available delta patches. It is **not a running service** — it's a scheduled GitHub Action that lists an S3 bucket and transforms the listing into static JSON files served by GitHub Pages.

> **Originally designed as a live Go HTTP server**, then briefly as a manifest generator over GitHub Releases. Revised again 2026-08-16: GitHub Releases' 2GB-per-file limit is a real risk for full Android image bundles, so build artifacts (full images and delta patches alike) now live in S3 instead. The "no always-on compute" shape is unchanged — still a scheduled listing + transform, not a service.

---

## How It Works

```
Every 6 hours (or on manual trigger)
           |
           v
  publish-manifest.yml (GitHub Actions)
           |
           +- list-s3-releases.sh
           |    aws s3api list-objects-v2 --bucket noxos-releases --prefix full/
           |    aws s3api list-objects-v2 --bucket noxos-releases --prefix patches/
           |
           +- build-manifest.sh (pure jq + bash, only network calls are sidecar fetches)
           |    For each object matching its naming pattern:
           |      full/noxos-<version>-<YYYYMMDD>-<channel>-<device>.zip
           |      patches/noxos-<from>-to-<to>-<YYYYMMDD>-<channel>-<device>.patch.zip
           |    - parse version(s), date, channel, device
           |    - fetch .sha256 / .changelog.txt sidecar objects, each degrading
           |      gracefully (null / empty) on failure, never crashing the run
           |    - build a JSON entry: url, size, timestamp, sha256[, changelog]
           |
           +- actions/upload-pages-artifact + actions/deploy-pages
              (Actions-based Pages deployment, not a gh-pages branch)
                    |
                    v
          GitHub Pages serves it at:
          https://parrothacker1.is-a.dev/noxos-server/<device>/<channel>.json
```

---

## Manifest Schema

```json
{
  "response": [
    {
      "device":      "cuttlefish",
      "type":        "stable",
      "incremental": "0.2.0",
      "filename":    "noxos-0.2.0-20260901-stable-cuttlefish.zip",
      "timestamp":   1725148800,
      "size":        1610612736,
      "sha256":      "abc123...",
      "version":     "0.2.0",
      "url":         "https://noxos-releases.s3.us-east-1.amazonaws.com/full/noxos-0.2.0-20260901-stable-cuttlefish.zip",
      "changelog":   "release notes"
    }
  ],
  "patches": [
    {
      "device":    "cuttlefish",
      "type":      "stable",
      "from":      "0.1.0",
      "to":        "0.2.0",
      "filename":  "noxos-0.1.0-to-0.2.0-20260901-stable-cuttlefish.patch.zip",
      "timestamp": 1725148800,
      "size":      123456789,
      "sha256":    "def456...",
      "url":       "https://noxos-releases.s3.us-east-1.amazonaws.com/patches/noxos-0.1.0-to-0.2.0-20260901-stable-cuttlefish.patch.zip"
    }
  ]
}
```

One file per device/channel (`docs/<device>/<channel>.json`). `response` is the full-image build list, sorted newest-first; `patches` is every available delta, also sorted newest-first. `sha256`/`changelog` are `null`/empty if their sidecar object was missing or unreachable at generation time.

**Client resolution logic:** compare the current `incremental` against `response[0].incremental`. If already current, stop. Otherwise, look for a `patches` entry where `from` equals the current version and `to` equals `response[0].incremental` — if found, download and apply that (smaller). If no matching single-hop patch exists, fall back to downloading `response[0]`'s full image. No N-hop patch chaining (see "Deliberate Non-Features").

---

## Release Naming Convention

```
Full images:   full/noxos-<version>-<YYYYMMDD>-<channel>-<device>.zip
Patches:       patches/noxos-<from_version>-to-<to_version>-<YYYYMMDD>-<channel>-<device>.patch.zip
Sidecars:      <same key> + ".sha256"                          (plain text, one hex hash)
               <same key minus ".zip"> + ".changelog.txt"       (full images only)

Examples:
  full/noxos-0.1.0-20260815-stable-cuttlefish.zip
  patches/noxos-0.1.0-to-0.2.0-20260901-stable-cuttlefish.patch.zip
```

Channels: `stable`, `nightly` (more can be added; each gets its own JSON file). Patches are generated elsewhere in the pipeline (`noxos-os`, via AOSP's `ota_from_target_files -i old.zip new.zip patch.zip`) between consecutive full releases only — this repo only catalogs whatever patch objects it finds under `patches/`, it doesn't generate them.

---

## Why Not a Live Server?

| Approach | Verdict |
|----------|---------|
| Persistent Go HTTP server | Always-on cost, maintenance burden, no real server-side logic yet |
| AWS Lambda / compute-on-request | No server-side logic that justifies it (no staged rollouts, no analytics) |
| Firebase Cloud Messaging (push) | Conflicts with GMS-independence — can't depend on Google services |
| Self-hosted UnifiedPush relay | Real infra this project doesn't need at this scope |
| **Scheduled GitHub Action -> Pages** | Zero cost, zero maintenance, no always-on anything |

---

## Deliberate Non-Features

- **No N-hop patch chaining across missed versions.** Real ROM projects (LineageOS, GrapheneOS) avoid this for the same reason — pre-building deltas for every version pair doesn't scale, and one failed hop mid-chain breaks the update. A device more than one release behind just re-downloads the latest full image. Single-hop patches (previous full release -> latest full release) are supported.
- **No push notifications.** Client polls on a schedule.
- **No compute-on-request.** An update check is a static file read; patch generation happens upstream in the build pipeline, not here.

---

## Hosted URL

```
https://parrothacker1.is-a.dev/noxos-server/<device>/<channel>.json
```

Custom domain configured via the account's `is-a.dev` subdomain. GitHub Pages is enabled with `build_type=workflow` (Actions-based deployment via `actions/deploy-pages`, no `gh-pages` branch involved).

---

## Configuration

`publish-manifest.yml` needs these set on the repo (Settings -> Secrets and variables -> Actions):

| Name | Kind | Purpose |
|------|------|---------|
| `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` | Secret | Read access to list the S3 bucket (`s3:ListBucket`) |
| `AWS_DEFAULT_REGION` | Variable | Region the bucket lives in |
| `NOXOS_S3_BUCKET` | Variable | Bucket name (defaults to `noxos-releases` if unset) |
| `NOXOS_S3_BASE_URL` | Variable | Public base URL used to build download links, e.g. `https://noxos-releases.s3.us-east-1.amazonaws.com` |

Devices download artifacts over plain HTTPS from `NOXOS_S3_BASE_URL`, so the bucket (or a CDN in front of it) needs public read on objects — the credentials above are only for the listing call, not for downloads.

---

## Verification Status

The transform logic is tested against a fixture (`testdata/s3-listing.json`) that includes an unreachable sidecar base URL — to explicitly verify the graceful-degradation path for both full images and patches. That test passes.

**Nothing here has run end-to-end against a real S3 bucket.** No bucket exists yet (Phase 1 infra hasn't been provisioned), so `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY`/`NOXOS_S3_BASE_URL` aren't configured either — the scheduled workflow will fail until both exist. Once they do, trigger manually:

```bash
gh workflow run publish-manifest.yml -R parrothacker1/noxos-server
```

Then check `https://parrothacker1.is-a.dev/noxos-server/cuttlefish/stable.json`.

---

<div align="center">
<sub>Part of <a href="https://github.com/parrothacker1/noxos">NoxOS</a></sub>
</div>

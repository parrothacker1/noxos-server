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

`noxos-server` generates and publishes the OTA update manifests that `noxos-app` clients query to discover new ROM releases. It is **not a running service** — it's a scheduled GitHub Action that transforms release metadata into static JSON files served by GitHub Pages.

> **Originally designed as a live Go HTTP server.** Scrapped on 2026-08-15 once it became clear that once artifacts live on GitHub Releases, an update check is just "read a small JSON file" — a scheduled GitHub Action does that without any always-on compute.

---

## How It Works

```
Every 6 hours (or on manual trigger)
           │
           ▼
  publish-manifest.yml (GitHub Actions)
           │
           ├─ fetch-releases.sh
           │    └─ gh api /repos/parrothacker1/noxos-os/releases
           │         Returns: list of releases + asset filenames
           │
           ├─ build-manifest.sh (pure jq + bash, network-free)
           │    └─ For each asset matching the naming pattern:
           │         noxos-<version>-<YYYYMMDD>-<channel>-<device>.zip
           │         ├─ Parse: version, date, channel, device
           │         ├─ Fetch SHA256 sidecar (.sha256 asset) — degrades
           │         │    gracefully to null on failure, never crashes
           │         └─ Build JSON entry: url, size, timestamp, sha256
           │
           └─ actions/upload-pages-artifact + actions/deploy-pages
              (Actions-based Pages deployment, not a gh-pages branch)
                    │
                    ▼
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
      "incremental": "v0.1.0",
      "filename":    "noxos-0.1.0-20260815-stable-cuttlefish.zip",
      "timestamp":   1723680000,
      "size":        1610612736,
      "sha256":      "abc123...",
      "version":     "0.1.0",
      "url":         "https://github.com/parrothacker1/noxos-os/releases/download/v0.1.0/noxos-0.1.0-20260815-stable-cuttlefish.zip",
      "changelog":   "release notes body"
    }
  ]
}
```

This is the exact shape `scripts/build-manifest.sh` emits — one file per device/channel (`docs/<device>/<channel>.json`), `response` is the full build list for that pair, sorted newest-first. `incremental` is the release's git tag; `sha256` is `null` if the `.sha256` sidecar asset was missing or unreachable at generation time. Clients compare their current `incremental` against `response[0].incremental`. If newer, they download the zip from `url`, verify the `sha256`, and apply the OTA via AOSP's standard `update_engine`.

---

## Release Naming Convention

Asset filenames must follow this exact pattern for `build-manifest.sh` to parse them:

```
noxos-<version>-<YYYYMMDD>-<channel>-<device>.zip

Examples:
  noxos-0.1.0-20260815-stable-cuttlefish.zip
  noxos-0.2.0-20261001-nightly-cuttlefish.zip
  noxos-1.0.0-20270201-stable-aosp_cf_arm64.zip
```

Channels: `stable`, `nightly` (more can be added; each gets its own JSON file).

---

## Why Not a Live Server?

| Approach | Verdict |
|----------|---------|
| Persistent Go HTTP server | ❌ Always-on cost, maintenance burden, no real server-side logic yet |
| AWS Lambda / compute-on-request | ❌ No server-side logic that justifies it (no staged rollouts, no analytics) |
| Firebase Cloud Messaging (push) | ❌ Conflicts with GMS-independence — can't depend on Google services |
| Self-hosted UnifiedPush relay | ❌ Real infra this project doesn't need at this scope |
| **Scheduled GitHub Action → Pages** | ✅ Zero cost, zero maintenance, no always-on anything |

---

## Deliberate Non-Features

- **No patch chaining.** Real ROM projects (LineageOS, GrapheneOS) don't do N-hop incremental chains — pre-building deltas for every version pair doesn't scale, and one failed hop mid-chain breaks the update. Devices re-download the latest full image.
- **No push notifications.** Client polls on a schedule.
- **No compute-on-request.** An update check is a static file read.

---

## Hosted URL

```
https://parrothacker1.is-a.dev/noxos-server/<device>/<channel>.json
```

Custom domain configured via the account's `is-a.dev` subdomain. GitHub Pages is enabled with `build_type=workflow` (Actions-based deployment via `actions/deploy-pages`, no `gh-pages` branch involved).

---

## Verification Status

The transform logic is tested against a fixture (`testdata/releases.json`) that includes an unreachable SHA256 sidecar URL — to explicitly verify the graceful-degradation path. That test passes.

The **end-to-end publish has never run against real `noxos-os` release data** — no real release has been cut yet (Phase 1 hasn't produced a build). Once `noxos-os` cuts its first release, trigger manually:

```bash
gh workflow run publish-manifest.yml -R parrothacker1/noxos-server
```

Then check `https://parrothacker1.is-a.dev/noxos-server/cuttlefish/stable.json`.

---

<div align="center">
<sub>Part of <a href="https://github.com/parrothacker1/noxos">NoxOS</a></sub>
</div>

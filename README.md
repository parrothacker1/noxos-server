# noxos-server

NoxOS OTA update server. Custom signed OTA channel using AOSP's `ota_from_target_files` tooling (that tooling lives in `noxos-os`, not here), self-hosted — same pattern as LineageOS/GrapheneOS/CalyxOS updater backends.

This repo is just the update-check API and static file serving of the signed OTA package zips. No build system, no signing, no device management UI, no database.

Part of [NoxOS](https://github.com/parrothacker1/noxos). Status: skeleton (Phase IV of the roadmap).

## API

`GET /api/v1/{device}/{type}/{incremental}`

Returns the OTA builds available for `device` on channel `type` (e.g. `nightly`), excluding any build matching the client's current `incremental`. Shape follows the LineageOS updater API convention:

```json
{
  "response": [
    {
      "device": "sunfish",
      "type": "nightly",
      "incremental": "eng.root.20260101.000000",
      "filename": "noxos-1.0-20260101-nightly-sunfish.zip",
      "timestamp": 1767225600,
      "size": 838860800,
      "sha256": "...",
      "version": "1.0",
      "url": "/builds/noxos-1.0-20260101-nightly-sunfish.zip"
    }
  ]
}
```

Build metadata is read from `builds/index.json` (checked in with one placeholder entry documenting the shape). The actual OTA package files are served statically from `builds/` at `/builds/<filename>`.

`GET /healthz` returns `200 ok`.

## Running locally

```sh
go run main.go
```

Listens on `:8080` by default. Override with `NOXOS_SERVER_ADDR` and `NOXOS_BUILDS_DIR` env vars.

```sh
curl http://localhost:8080/api/v1/sunfish/nightly/none
```

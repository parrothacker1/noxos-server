#!/usr/bin/env bash
# Transforms a GitHub Releases API response (array of release objects) into
# static per-device/channel OTA manifests. Pure transform, no network calls
# except optionally curling .sha256 sidecar assets - kept separate from
# fetch-releases.sh so this half is unit-testable against a fixture.
#
# Usage: build-manifest.sh <releases.json> <out_dir>
#
# Asset naming convention: noxos-<version>-<YYYYMMDD>-<channel>-<device>.zip
# Optional sidecar: same name + ".sha256" (plain text, one hex hash).
set -euo pipefail

RELEASES_JSON="${1:?usage: build-manifest.sh <releases.json> <out_dir>}"
OUT_DIR="${2:?usage: build-manifest.sh <releases.json> <out_dir>}"
FILENAME_RE='^noxos-([^-]+)-([0-9]{8})-([^-]+)-([^.]+)\.zip$'

mkdir -p "$OUT_DIR"

# Flatten releases -> candidate zip assets, carrying along the sidecar's
# download URL (if present) so we don't have to re-scan assets per entry.
candidates=$(jq -c '
  [.[] as $r | ($r.assets // [])[] as $a |
    select($a.name | test("\\.zip$")) |
    {
      tag: $r.tag_name,
      published_at: $r.published_at,
      body: ($r.body // ""),
      name: $a.name,
      size: $a.size,
      url: $a.browser_download_url,
      sha256_url: (($r.assets[] | select(.name == ($a.name + ".sha256")) | .browser_download_url) // null)
    }
  ]
' "$RELEASES_JSON")

work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT

echo "$candidates" | jq -c '.[]' | while read -r entry; do
  name=$(jq -r '.name' <<<"$entry")
  [[ "$name" =~ $FILENAME_RE ]] || continue
  version="${BASH_REMATCH[1]}"
  channel="${BASH_REMATCH[3]}"
  device="${BASH_REMATCH[4]}"

  sha256_url=$(jq -r '.sha256_url' <<<"$entry")
  sha256="null"
  if [[ "$sha256_url" != "null" ]]; then
    if ! sha256=$(curl -fsSL --max-time 10 "$sha256_url" 2>/dev/null | awk '{print $1}') || [[ -z "$sha256" ]]; then
      echo "warning: could not fetch sha256 sidecar for $name, leaving null" >&2
      sha256="null"
    fi
  fi

  published_at=$(jq -r '.published_at' <<<"$entry")
  timestamp=$(date -u -d "$published_at" +%s)

  build=$(jq -n \
    --arg device "$device" \
    --arg type "$channel" \
    --arg incremental "$(jq -r '.tag' <<<"$entry")" \
    --arg filename "$name" \
    --argjson timestamp "$timestamp" \
    --argjson size "$(jq -r '.size' <<<"$entry")" \
    --arg sha256 "$sha256" \
    --arg version "$version" \
    --arg url "$(jq -r '.url' <<<"$entry")" \
    --arg changelog "$(jq -r '.body' <<<"$entry")" \
    '{device:$device,type:$type,incremental:$incremental,filename:$filename,
      timestamp:$timestamp,size:$size,
      sha256:(if $sha256=="null" then null else $sha256 end),
      version:$version,url:$url,changelog:$changelog}')

  mkdir -p "$work_dir/$device"
  echo "$build" >>"$work_dir/$device/$channel.jsonl"
done

rm -rf "${OUT_DIR:?}"/*
for f in "$work_dir"/*/*.jsonl; do
  [[ -e "$f" ]] || continue
  device=$(basename "$(dirname "$f")")
  channel=$(basename "$f" .jsonl)
  mkdir -p "$OUT_DIR/$device"
  jq -s 'sort_by(-.timestamp) | {response: .}' "$f" >"$OUT_DIR/$device/$channel.json"
done

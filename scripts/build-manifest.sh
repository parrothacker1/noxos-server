#!/usr/bin/env bash
set -euo pipefail

LISTING_JSON="${1:?usage: build-manifest.sh <listing.json> <base_url> <out_dir>}"
BASE_URL="${2:?usage: build-manifest.sh <listing.json> <base_url> <out_dir>}"
OUT_DIR="${3:?usage: build-manifest.sh <listing.json> <base_url> <out_dir>}"

FULL_RE='^full/noxos-([^-]+)-([0-9]{8})-([^-]+)-([^.]+)\.zip$'
PATCH_RE='^patches/noxos-([^-]+)-to-([^-]+)-([0-9]{8})-([^-]+)-([^.]+)\.patch\.zip$'

mkdir -p "$OUT_DIR"

fetch_sidecar() {
  curl -fsSL --max-time 10 "$1" 2>/dev/null || true
}

work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT

jq -c '.full[]' "$LISTING_JSON" | while read -r obj; do
  key=$(jq -r '.Key' <<<"$obj")
  [[ "$key" =~ $FULL_RE ]] || continue
  version="${BASH_REMATCH[1]}"
  channel="${BASH_REMATCH[3]}"
  device="${BASH_REMATCH[4]}"

  size=$(jq -r '.Size' <<<"$obj")
  timestamp=$(date -u -d "$(jq -r '.LastModified' <<<"$obj")" +%s)
  url="${BASE_URL%/}/${key}"

  sha256=$(fetch_sidecar "${url}.sha256" | awk '{print $1}')
  if [[ -z "$sha256" ]]; then
    sha256="null"
    echo "warning: no sha256 sidecar for $key" >&2
  fi

  changelog=$(fetch_sidecar "${url%.zip}.changelog.txt")

  build=$(jq -n \
    --arg device "$device" --arg type "$channel" --arg incremental "$version" \
    --arg filename "$(basename "$key")" --argjson timestamp "$timestamp" \
    --argjson size "$size" --arg sha256 "$sha256" --arg version "$version" \
    --arg url "$url" --arg changelog "$changelog" \
    '{device:$device,type:$type,incremental:$incremental,filename:$filename,
      timestamp:$timestamp,size:$size,
      sha256:(if $sha256=="null" then null else $sha256 end),
      version:$version,url:$url,changelog:$changelog}')

  mkdir -p "$work_dir/$device"
  echo "$build" >>"$work_dir/$device/$channel.full.jsonl"
done

jq -c '.patches[]' "$LISTING_JSON" | while read -r obj; do
  key=$(jq -r '.Key' <<<"$obj")
  [[ "$key" =~ $PATCH_RE ]] || continue
  from="${BASH_REMATCH[1]}"
  to="${BASH_REMATCH[2]}"
  channel="${BASH_REMATCH[4]}"
  device="${BASH_REMATCH[5]}"

  size=$(jq -r '.Size' <<<"$obj")
  timestamp=$(date -u -d "$(jq -r '.LastModified' <<<"$obj")" +%s)
  url="${BASE_URL%/}/${key}"

  sha256=$(fetch_sidecar "${url}.sha256" | awk '{print $1}')
  if [[ -z "$sha256" ]]; then
    sha256="null"
    echo "warning: no sha256 sidecar for $key" >&2
  fi

  patch=$(jq -n \
    --arg device "$device" --arg type "$channel" --arg from "$from" --arg to "$to" \
    --arg filename "$(basename "$key")" --argjson timestamp "$timestamp" \
    --argjson size "$size" --arg sha256 "$sha256" --arg url "$url" \
    '{device:$device,type:$type,from:$from,to:$to,filename:$filename,
      timestamp:$timestamp,size:$size,
      sha256:(if $sha256=="null" then null else $sha256 end),url:$url}')

  mkdir -p "$work_dir/$device"
  echo "$patch" >>"$work_dir/$device/$channel.patch.jsonl"
done

rm -rf "${OUT_DIR:?}"/*
shopt -s nullglob

for f in "$work_dir"/*/*.full.jsonl; do
  device=$(basename "$(dirname "$f")")
  channel=$(basename "$f" .full.jsonl)
  mkdir -p "$OUT_DIR/$device"

  response=$(jq -s 'sort_by(-.timestamp)' "$f")
  patch_file="$work_dir/$device/$channel.patch.jsonl"
  if [[ -e "$patch_file" ]]; then
    patches=$(jq -s 'sort_by(-.timestamp)' "$patch_file")
  else
    patches="[]"
  fi

  jq -n --argjson response "$response" --argjson patches "$patches" \
    '{response:$response, patches:$patches}' >"$OUT_DIR/$device/$channel.json"
done

for f in "$work_dir"/*/*.patch.jsonl; do
  device=$(basename "$(dirname "$f")")
  channel=$(basename "$f" .patch.jsonl)
  out_file="$OUT_DIR/$device/$channel.json"
  [[ -e "$out_file" ]] && continue

  mkdir -p "$OUT_DIR/$device"
  patches=$(jq -s 'sort_by(-.timestamp)' "$f")
  jq -n --argjson patches "$patches" '{response:[], patches:$patches}' >"$out_file"
done

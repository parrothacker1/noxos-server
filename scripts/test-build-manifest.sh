#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIXTURE="$SCRIPT_DIR/../testdata/s3-listing.json"
BASE_URL="https://example.invalid"
OUT_DIR="$(mktemp -d)"
trap 'rm -rf "$OUT_DIR"' EXIT

"$SCRIPT_DIR/build-manifest.sh" "$FIXTURE" "$BASE_URL" "$OUT_DIR"

fail() { echo "FAIL: $1" >&2; exit 1; }

[[ -f "$OUT_DIR/sunfish/nightly.json" ]] || fail "sunfish/nightly.json missing"
[[ -f "$OUT_DIR/cf_x86_64/nightly.json" ]] || fail "cf_x86_64/nightly.json missing"

sunfish_count=$(jq '.response | length' "$OUT_DIR/sunfish/nightly.json")
[[ "$sunfish_count" == "2" ]] || fail "expected 2 sunfish builds, got $sunfish_count"

newest_version=$(jq -r '.response[0].incremental' "$OUT_DIR/sunfish/nightly.json")
[[ "$newest_version" == "1.1" ]] || fail "expected newest build first, got $newest_version"

oldest_version=$(jq -r '.response[1].incremental' "$OUT_DIR/sunfish/nightly.json")
[[ "$oldest_version" == "1.0" ]] || fail "expected oldest build second, got $oldest_version"

sha_for_newest=$(jq -r '.response[0].sha256' "$OUT_DIR/sunfish/nightly.json")
[[ "$sha_for_newest" == "null" ]] || fail "expected null sha256 for unreachable sidecar, got $sha_for_newest"

for field in device type incremental filename timestamp size sha256 version url changelog; do
  jq -e "has(\"$field\")" <<<"$(jq '.response[0]' "$OUT_DIR/sunfish/nightly.json")" >/dev/null \
    || fail "missing field $field in manifest entry"
done

cf_url=$(jq -r '.response[0].url' "$OUT_DIR/cf_x86_64/nightly.json")
[[ "$cf_url" == *"cf_x86_64.zip" ]] || fail "unexpected cf_x86_64 url: $cf_url"

sunfish_patch_count=$(jq '.patches | length' "$OUT_DIR/sunfish/nightly.json")
[[ "$sunfish_patch_count" == "1" ]] || fail "expected 1 sunfish patch, got $sunfish_patch_count"

patch_from=$(jq -r '.patches[0].from' "$OUT_DIR/sunfish/nightly.json")
patch_to=$(jq -r '.patches[0].to' "$OUT_DIR/sunfish/nightly.json")
[[ "$patch_from" == "1.0" && "$patch_to" == "1.1" ]] || fail "unexpected patch range: $patch_from -> $patch_to"

cf_patch_count=$(jq '.patches | length' "$OUT_DIR/cf_x86_64/nightly.json")
[[ "$cf_patch_count" == "0" ]] || fail "expected 0 cf_x86_64 patches, got $cf_patch_count"

echo "ok: build-manifest.sh transform tests passed"

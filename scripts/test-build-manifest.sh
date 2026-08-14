#!/usr/bin/env bash
# One runnable check for the manifest transform: feeds a fixture releases.json
# through build-manifest.sh and asserts the output shape/filtering/sorting.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIXTURE="$SCRIPT_DIR/../testdata/releases.json"
OUT_DIR="$(mktemp -d)"
trap 'rm -rf "$OUT_DIR"' EXIT

"$SCRIPT_DIR/build-manifest.sh" "$FIXTURE" "$OUT_DIR"

fail() { echo "FAIL: $1" >&2; exit 1; }

# Two devices should show up: sunfish (2 builds) and cf_x86_64 (1 build).
# source.tar.gz must not leak into any manifest.
[[ -f "$OUT_DIR/sunfish/nightly.json" ]] || fail "sunfish/nightly.json missing"
[[ -f "$OUT_DIR/cf_x86_64/nightly.json" ]] || fail "cf_x86_64/nightly.json missing"

sunfish_count=$(jq '.response | length' "$OUT_DIR/sunfish/nightly.json")
[[ "$sunfish_count" == "2" ]] || fail "expected 2 sunfish builds, got $sunfish_count"

# Newest (v1.1.0, 2026-02-01) must sort first.
newest_tag=$(jq -r '.response[0].incremental' "$OUT_DIR/sunfish/nightly.json")
[[ "$newest_tag" == "v1.1.0" ]] || fail "expected newest build first, got $newest_tag"

oldest_tag=$(jq -r '.response[1].incremental' "$OUT_DIR/sunfish/nightly.json")
[[ "$oldest_tag" == "v1.0.0" ]] || fail "expected oldest build second, got $oldest_tag"

# Unreachable sidecar URL must degrade to null, not crash the run.
sha_for_newest=$(jq -r '.response[0].sha256' "$OUT_DIR/sunfish/nightly.json")
[[ "$sha_for_newest" == "null" ]] || fail "expected null sha256 for unreachable sidecar, got $sha_for_newest"

# Every required field present on a sample entry.
for field in device type incremental filename timestamp size sha256 version url changelog; do
  jq -e "has(\"$field\")" <<<"$(jq '.response[0]' "$OUT_DIR/sunfish/nightly.json")" >/dev/null \
    || fail "missing field $field in manifest entry"
done

cf_url=$(jq -r '.response[0].url' "$OUT_DIR/cf_x86_64/nightly.json")
[[ "$cf_url" == *"cf_x86_64.zip" ]] || fail "unexpected cf_x86_64 url: $cf_url"

echo "ok: build-manifest.sh transform tests passed"

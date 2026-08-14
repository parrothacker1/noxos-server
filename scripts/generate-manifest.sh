#!/usr/bin/env bash
# Full pipeline: fetch releases from noxos-os, rebuild the static manifest
# tree from scratch. Idempotent by design - always regenerated from GitHub's
# release list, never appended to, so a missed run never causes drift.
#
# Usage: generate-manifest.sh [out_dir]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT_DIR="${1:-docs}"

releases_json="$(mktemp)"
trap 'rm -f "$releases_json"' EXIT

"$SCRIPT_DIR/fetch-releases.sh" >"$releases_json"
"$SCRIPT_DIR/build-manifest.sh" "$releases_json" "$OUT_DIR"

echo "manifest written to $OUT_DIR"

#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUCKET="${NOXOS_S3_BUCKET:-noxos-releases}"
BASE_URL="${NOXOS_S3_BASE_URL:?NOXOS_S3_BASE_URL must be set (e.g. https://noxos-releases.s3.us-east-1.amazonaws.com)}"
OUT_DIR="${1:-docs}"

listing_json="$(mktemp)"
trap 'rm -f "$listing_json"' EXIT

"$SCRIPT_DIR/list-s3-releases.sh" "$BUCKET" >"$listing_json"
"$SCRIPT_DIR/build-manifest.sh" "$listing_json" "$BASE_URL" "$OUT_DIR"

echo "manifest written to $OUT_DIR"

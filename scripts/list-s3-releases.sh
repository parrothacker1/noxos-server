#!/usr/bin/env bash
set -euo pipefail

BUCKET="${1:-${NOXOS_S3_BUCKET:-noxos-releases}}"

list_prefix() {
  aws s3api list-objects-v2 --bucket "$BUCKET" --prefix "$1" --output json \
    | jq -c '.Contents // []'
}

jq -n --argjson full "$(list_prefix "full/")" --argjson patches "$(list_prefix "patches/")" \
  '{full: $full, patches: $patches}'

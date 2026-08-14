#!/usr/bin/env bash
# Thin wrapper around the GitHub API: dumps every release (with assets) of
# the repo that actually produces OTA builds. Separate from build-manifest.sh
# so the transform logic stays testable without network access.
#
# Usage: fetch-releases.sh [owner/repo] > releases.json
set -euo pipefail

REPO="${1:-parrothacker1/noxos-os}"
gh api "repos/${REPO}/releases" --paginate --slurp | jq 'add // []'

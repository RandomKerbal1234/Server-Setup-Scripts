#!/usr/bin/env bash
# make-manifest.sh - regenerate MANIFEST.sha256 and secrets/SHA256SUMS.
#
# Run from anywhere; paths are written relative to the bundle root.
set -euo pipefail

BUNDLE_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$BUNDLE_DIR"

if command -v sha256sum >/dev/null 2>&1; then
  hash_file() { sha256sum "$1" | awk '{print $1}'; }
else
  hash_file() { shasum -a 256 "$1" | awk '{print $1}'; }
fi

tmp=$(mktemp "${TMPDIR:-/tmp}/manifest.XXXXXX")
trap 'rm -f "$tmp"' EXIT

find . -type f \
  ! -path './raw/*' \
  ! -path './secrets/*' \
  ! -name 'MANIFEST.sha256' \
  ! -name 'MANIFEST' \
  ! -name '.DS_Store' \
  | sort | sed 's|^\./||' | while IFS= read -r f; do
      printf '%s  %s\n' "$(hash_file "$f")" "$f"
    done > "$tmp"
mv "$tmp" MANIFEST.sha256
chmod 644 MANIFEST.sha256
trap - EXIT

tmp=$(mktemp "${TMPDIR:-/tmp}/secrets-manifest.XXXXXX")
trap 'rm -f "$tmp"' EXIT
find secrets -type f ! -name 'SHA256SUMS' | sort | while IFS= read -r f; do
  printf '%s  %s\n' "$(hash_file "$f")" "$f"
done > "$tmp"
mv "$tmp" secrets/SHA256SUMS
chmod 600 secrets/SHA256SUMS
trap - EXIT

echo "wrote MANIFEST.sha256 ($(wc -l < MANIFEST.sha256 | tr -d ' ') files)"
echo "wrote secrets/SHA256SUMS ($(wc -l < secrets/SHA256SUMS | tr -d ' ') files)"

#!/usr/bin/env bash
#
# Stage the Deck landing page into a directory ready to serve or deploy.
#
# This is a COPY step, not a build: the page is plain static HTML + CSS, and
# there is deliberately no JS/npm toolchain. Assets that live elsewhere in the
# repo (the Deck mark and the screenshots) are copied in here so they keep one
# home in git and the page can reference them relatively as `assets/…`.
#
# Usage:
#   scripts/stage-site.sh [OUT_DIR]     # default: .site-build
#
# Local preview:
#   scripts/stage-site.sh && python3 -m http.server -d .site-build 8000
#
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
out="${1:-$repo_root/.site-build}"

rm -rf "$out"
mkdir -p "$out/assets"

# The page source.
cp -R "$repo_root/site/." "$out/"

# Assets, from their single home in the repo.
cp "$repo_root/docs/deck.svg" "$out/assets/deck.svg"
for shot in A1 A3 A5; do
  cp "$repo_root/docs/screenshots/$shot.png" "$out/assets/$shot.png"
done

echo "staged -> $out"

#!/usr/bin/env bash
#
# Assert the staged landing page carries the install copy it must, in the
# right order, and does not invent a flag that no longer exists.
#
# Background: the install steps are duplicated in four places — README.md, the
# Homebrew cask caveats, the release-notes job in deck.yml, and site/index.html.
# This is a FLOOR, not a parity check: it proves the page has the required
# strings and the correct order, not that they match the other three
# byte-for-byte. A release that changes the install steps must update all four.
#
# Usage:
#   scripts/stage-site.sh && scripts/check-site.sh [STAGED_DIR]
#
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
dir="${1:-$repo_root/.site-build}"
file="$dir/index.html"

fail() { echo "check-site: FAIL: $1" >&2; exit 1; }

[ -f "$file" ] || fail "no $file (run scripts/stage-site.sh first)"

# Required copy.
grep -Fq 'brew install --cask haqaliz/deck/deck' "$file" \
  || fail "missing the Homebrew install command"
grep -Fq 'releases/latest' "$file" \
  || fail "missing the latest-release download link"
grep -Fq 'xattr -dr com.apple.quarantine /Applications/Deck.app' "$file" \
  || fail "missing the quarantine-clearing command"
grep -Fq 'before opening Deck' "$file" \
  || fail "missing the run-this-before-first-launch warning"

# The removed flag must never reappear.
grep -Fq -- '--no-quarantine' "$file" \
  && fail "must not mention --no-quarantine (Homebrew removed the flag)"

# Every widget must be named.
for name in LiveBox OpenBox NetBox BatBox GitBox DevBox ClipBox WeatherBox \
            ClockBox ShipBox TaskBox CalBox PRBox MarketBox; do
  grep -Fq "$name" "$file" || fail "missing widget name: $name"
done

# Order: the quarantine step must come after the install command.
brew_line="$(grep -nF 'brew install --cask haqaliz/deck/deck' "$file" | head -1 | cut -d: -f1)"
xattr_line="$(grep -nF 'xattr -dr com.apple.quarantine' "$file" | head -1 | cut -d: -f1)"
[ "${xattr_line:-0}" -gt "${brew_line:-0}" ] \
  || fail "the quarantine step must appear after the install command"

echo "check-site: ok"

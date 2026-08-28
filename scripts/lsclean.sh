#!/bin/bash
# lsclean.sh — repair widget rendering when LaunchServices holds stale Deck bundles.
#
# Symptom: every Deck widget on the desktop renders as the WidgetKit placeholder
# (text as grey blocks, charts still drawn) at every size. chronod logs
#   WidgetArchiver.ValidationError.bundleStubNotSupported
#   "Bundle version did not match; LaunchServices DB may need to be rebuilt"
# for every timeline reload, so no rendered timeline is ever archived.
#
# Cause: dev builds (native/build*, .claude/worktrees/*/native/build*) register
# their own copy of com.deck.app / com.deck.app.widgets with LaunchServices.
# Once several versions — or bundles whose worktree has since been deleted —
# are registered, WidgetKit resolves the wrong bundle and rejects every render.
#
# Fix: unregister every Deck bundle outside /Applications, re-register the
# installed app, restart chronod.

set -u

source "$(dirname "${BASH_SOURCE[0]}")/lib/ids.sh"
LSR=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

stale=$("$LSR" -dump 2>/dev/null \
  | grep -E "^path:.*Deck\.app( |$)" \
  | sed 's/^path: *//; s/ *(0x[0-9a-f]*) *$//' \
  | grep -v '^/Applications/' | sort -u)

if [[ -n "$stale" ]]; then
  echo "unregistering $(echo "$stale" | wc -l | tr -d ' ') stale Deck bundle(s):"
  while IFS= read -r p; do
    echo "  $p"
    "$LSR" -u "$p" >/dev/null 2>&1
  done <<< "$stale"
else
  echo "no stale Deck bundles registered"
fi

if [[ -d /Applications/Deck.app ]]; then
  "$LSR" -f -R /Applications/Deck.app >/dev/null 2>&1
  echo "re-registered /Applications/Deck.app"
else
  echo "warning: /Applications/Deck.app not installed" >&2
fi

killall chronod 2>/dev/null && echo "restarted chronod"

echo
echo "verify (widgets should stop showing placeholders within ~60s):"
echo "  log show --last 2m --predicate 'process == \"chronod\"' --style compact \\"
echo "    | grep '${DECK_APP_ID}::' | grep -oE 'reload: (succeeded|failed)' | sort | uniq -c"

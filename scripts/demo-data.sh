#!/usr/bin/env bash
# demo-data.sh — swap the widget snapshots for presentable demo content so the
# widgets can be screenshotted without publishing the user's calendar, work
# items, clipboard and repo paths.
#
#   scripts/demo-data.sh on     # back up real snapshots, install demo data
#   scripts/demo-data.sh off    # restore the real snapshots
#
# It sanitizes rather than fabricates: each snapshot keeps its real structure,
# timestamps and numbers, and only the identifying strings are replaced. That
# way the widgets cannot fall back to "no data" because of a schema mismatch.
#
# LiveBox, NetBox, BatBox and ClockBox sample themselves inside the widget, so
# they are untouched — they show real (and harmless) CPU, network, battery and
# clock values.
#
# The agents and the Deck app are stopped while demo data is in place, because
# both rewrite these files. Widgets pick the new content up on their next
# timeline tick, so allow up to 60 seconds before capturing.
set -euo pipefail

CONTAINER="$HOME/Library/Containers/com.deck.app.widgets/Data/Library/Application Support/Deck"
BACKUP="$HOME/Library/Application Support/Deck/demo-backup"
SNAPSHOTS=(calbox taskbox clipbox gitbox shipbox devbox weather processes openbox)

agents_stop() {
  osascript -e 'quit app "Deck"' 2>/dev/null || true
  launchctl bootout "gui/$(id -u)/com.deck.agent" 2>/dev/null || true
  launchctl bootout "gui/$(id -u)/com.deck.agent.processes" 2>/dev/null || true
}

agents_start() {
  launchctl bootstrap "gui/$(id -u)" "$HOME/Library/LaunchAgents/com.deck.agent.plist" 2>/dev/null || true
  launchctl bootstrap "gui/$(id -u)" "$HOME/Library/LaunchAgents/com.deck.agent.processes.plist" 2>/dev/null || true
}

case "${1:-}" in
on)
  [ -d "$CONTAINER" ] || { echo "No widget container at $CONTAINER" >&2; exit 1; }
  if [ -d "$BACKUP" ]; then
    echo "Demo data already installed (backup exists at $BACKUP)." >&2
    echo "Run '$0 off' first." >&2
    exit 1
  fi
  agents_stop
  mkdir -p "$BACKUP"
  for name in "${SNAPSHOTS[@]}"; do
    [ -f "$CONTAINER/$name.json" ] && cp "$CONTAINER/$name.json" "$BACKUP/$name.json"
  done
  CONTAINER="$CONTAINER" python3 "$(dirname "$0")/demo_data.py"
  echo "Demo data installed. Backup: $BACKUP"
  echo "Wait ~60s for the widgets to pick it up, then capture."
  ;;
off)
  [ -d "$BACKUP" ] || { echo "No backup at $BACKUP — nothing to restore." >&2; exit 1; }
  for name in "${SNAPSHOTS[@]}"; do
    [ -f "$BACKUP/$name.json" ] && mv "$BACKUP/$name.json" "$CONTAINER/$name.json"
  done
  rmdir "$BACKUP" 2>/dev/null || true
  agents_start
  open -a Deck 2>/dev/null || true
  echo "Real snapshots restored and agents restarted."
  ;;
*)
  echo "usage: $0 {on|off}" >&2
  exit 2
  ;;
esac

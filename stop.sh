#!/bin/bash
# Stop a running deck widget.
# Usage: ./stop.sh <LiveBox|OpenBox|NetBox>
DIR="$(cd "$(dirname "$0")" && pwd)"

WIDGET="${1:?Usage: ./stop.sh <LiveBox|OpenBox|NetBox>}"

case "$WIDGET" in
  LiveBox|OpenBox|NetBox) ;;
  *) echo "Unknown widget: $WIDGET (expected LiveBox, OpenBox, or NetBox)" >&2; exit 1 ;;
esac

if pgrep -x "$WIDGET" >/dev/null; then
  pkill -x "$WIDGET"
  echo "$WIDGET stopped"
else
  echo "$WIDGET is not running"
fi

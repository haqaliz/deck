#!/bin/bash
# Stop a running deck widget.
# Usage: ./stop.sh <LiveBox|OpenBox|NetBox|BatBox>
DIR="$(cd "$(dirname "$0")" && pwd)"

WIDGET="${1:?Usage: ./stop.sh <LiveBox|OpenBox|NetBox|BatBox>}"

case "$WIDGET" in
  LiveBox|OpenBox|NetBox|BatBox) ;;
  *) echo "Unknown widget: $WIDGET (expected LiveBox, OpenBox, NetBox, or BatBox)" >&2; exit 1 ;;
esac

if pgrep -x "$WIDGET" >/dev/null; then
  pkill -x "$WIDGET"
  echo "$WIDGET stopped"
else
  echo "$WIDGET is not running"
fi

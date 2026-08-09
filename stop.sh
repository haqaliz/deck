#!/bin/bash
# Stop a running deck widget.
# Usage: ./stop.sh <LiveBox|OpenBox|NetBox|BatBox|GitBox>
DIR="$(cd "$(dirname "$0")" && pwd)"

WIDGET="${1:?Usage: ./stop.sh <LiveBox|OpenBox|NetBox|BatBox|GitBox>}"

case "$WIDGET" in
  LiveBox|OpenBox|NetBox|BatBox|GitBox) ;;
  *) echo "Unknown widget: $WIDGET (expected LiveBox, OpenBox, NetBox, BatBox, or GitBox)" >&2; exit 1 ;;
esac

if pgrep -x "$WIDGET" >/dev/null; then
  pkill -x "$WIDGET"
  echo "$WIDGET stopped"
else
  echo "$WIDGET is not running"
fi

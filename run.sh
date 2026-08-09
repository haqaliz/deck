#!/bin/bash
# Start a deck widget in the background.
# Usage: ./run.sh <LiveBox|OpenBox|NetBox|BatBox> [widget args...]
#   ./run.sh NetBox --corner tl --margin 20
# Stop with: ./stop.sh <LiveBox|OpenBox|NetBox|BatBox>
set -e
DIR="$(cd "$(dirname "$0")" && pwd)"

WIDGET="${1:-LiveBox}"
shift || true

case "$WIDGET" in
  LiveBox|OpenBox|NetBox|BatBox) ;;
  *) echo "Unknown widget: $WIDGET (expected LiveBox, OpenBox, NetBox, or BatBox)" >&2; exit 1 ;;
esac

if pgrep -x "$WIDGET" >/dev/null; then
  echo "$WIDGET is already running — stop it with: ./stop.sh $WIDGET" >&2
  exit 1
fi

swift build -c release --package-path "$DIR" >/dev/null

BIN="$DIR/.build/release/$WIDGET"
LOG="/tmp/deck-$WIDGET.log"
nohup "$BIN" "$@" >"$LOG" 2>&1 &

echo "$WIDGET started (pid $!) — log: $LOG"
echo "stop with: ./stop.sh $WIDGET"

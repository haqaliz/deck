#!/bin/bash
# Start every deck widget in the background.
# Stop with: ./stop-all.sh
set -e
DIR="$(cd "$(dirname "$0")" && pwd)"

swift build -c release --package-path "$DIR" >/dev/null

for WIDGET in LiveBox OpenBox NetBox BatBox GitBox; do
  if pgrep -x "$WIDGET" >/dev/null; then
    echo "$WIDGET already running — skipping"
    continue
  fi
  LOG="/tmp/deck-$WIDGET.log"
  nohup "$DIR/.build/release/$WIDGET" >"$LOG" 2>&1 &
  echo "$WIDGET started (pid $!) — log: $LOG"
done

echo "stop all with: ./stop-all.sh"

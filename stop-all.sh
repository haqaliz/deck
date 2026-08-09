#!/bin/bash
# Stop every running deck widget.
DIR="$(cd "$(dirname "$0")" && pwd)"

for WIDGET in LiveBox OpenBox NetBox BatBox GitBox; do
  if pgrep -x "$WIDGET" >/dev/null; then
    pkill -x "$WIDGET"
    echo "$WIDGET stopped"
  else
    echo "$WIDGET was not running"
  fi
done

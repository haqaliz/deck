#!/bin/bash
# container-repair.sh — rebuild the widget container skeleton after an
# incomplete uninstall.
#
# Symptom: every Deck widget renders as an empty rounded rect — background but
# no content — at every size, and the gallery previews are blank too. Nothing
# else looks wrong: codesign validates, `pluginkit -m` lists the extension at
# the right version, LaunchServices holds exactly one bundle, and there are no
# crash reports.
#
# chronod logs the real cause, one line above the misleading one:
#   [com.deck.app::com.deck.app.widgets:<Kind>:systemMedium…] on local reload:
#     could not create file handle because
#     ChronoKit.WidgetCacheManager.CacheManagementError.unsupportedEntryKey
#   Reload failed: CHSErrorDomain (1300) "extensionNotFound"
#
# `extensionNotFound` is a red herring — the extension is fine. chronod writes
# each rendered timeline into the widget's own container at
# Data/SystemData/com.apple.chrono/timelines/<Kind>/, and it cannot create that
# file, so it fails before ever asking the extension to render.
#
# Cause: `rm -rf ~/Library/Containers/com.deck.app.widgets` deletes the
# directory tree but CANNOT delete .com.apple.containermanagerd.metadata.plist
# (SIP-protected; it fails with "Operation not permitted"). Because that plist
# survives, containermanagerd still considers the container provisioned and
# never rebuilds the skeleton — leaving no Library/Caches, no SystemData, no
# Preferences for chronod to write into.
#
# Fix: recreate the standard skeleton, mode 700, matching any healthy widget
# container (compare against e.g. ~/Library/Containers/<any>.widgetextension).
#
# Prevention: remove the widgets from the desktop BEFORE uninstalling, and
# prefer leaving the container alone unless you specifically want to reset
# settings. If you must wipe it, run this afterwards.

set -u

source "$(dirname "${BASH_SOURCE[0]}")/lib/ids.sh"
CONTAINER="$DECK_CONTAINER"
DATA="$CONTAINER/Data"

if [[ ! -d "$CONTAINER" ]]; then
  echo "no widget container at $CONTAINER — nothing to repair"
  echo "(it is created when the widget extension first runs)"
  exit 0
fi

DIRS=(
  "Documents"
  "tmp"
  "SystemData"
  "SystemData/com.apple.chrono"
  "SystemData/com.apple.chrono/controlPreviews"
  "Library"
  "Library/Application Scripts"
  "Library/Application Support"
  "Library/Caches"
  "Library/Images"
  "Library/Logs"
  "Library/Preferences"
  "Library/Saved Application State"
)

created=0
for d in "${DIRS[@]}"; do
  if [[ ! -d "$DATA/$d" ]]; then
    mkdir -p "$DATA/$d" && created=$((created + 1))
    echo "  created Data/$d"
  fi
done

# Sandboxed containers are 700 throughout; a 755 left by a manual mkdir is a
# mismatch worth correcting even when nothing was missing.
chmod 700 "$DATA" 2>/dev/null
for d in "${DIRS[@]}"; do
  [[ -d "$DATA/$d" ]] && chmod 700 "$DATA/$d" 2>/dev/null
done

if [[ $created -eq 0 ]]; then
  echo "skeleton already complete ($((${#DIRS[@]})) directories); permissions normalised to 700"
else
  echo "repaired $created missing director$([[ $created -eq 1 ]] && echo y || echo ies)"
fi

killall chronod 2>/dev/null && echo "restarted chronod"

echo
echo "verify — a rendering widget writes a timeline cache within ~60s:"
echo "  ls \"$DATA/SystemData/com.apple.chrono/timelines/\""
echo "and LiveBox/NetBox/BatBox write a render heartbeat:"
echo "  ls \"$DATA/Library/Application Support/\" | grep Widget"

#!/bin/zsh
# Deck soak harness — stresses the agent write paths and asserts no crash,
# valid JSON snapshots, and no temp-file leftovers. Runs in minutes, not
# hours; the 24h wall-clock soak is documented in
# docs/planning/crash-robustness-pass/runbook-24h.md.
#
# What it does:
#   1. Isolates from the installed agents: pre-SMAppService installs have their
#      two LaunchAgents in ~/Library/LaunchAgents, which the soak boots out and
#      re-bootstraps; SMAppService-registered agents (plists in the signed
#      bundle) are left running — the parse-only checks tolerate concurrency.
#   2. Backs up the snapshot container and writes a throwaway settings fixture
#      (fixed weather location; no ShipBox repo/token, no OpenBox server/token —
#      those paths skip; weather may fail offline — that must be a skip, not a
#      crash).
#   3. Runs SOAK_FULL (200) full agent runs + SOAK_PROCESSES (200) --processes
#      runs, including SOAK_OVERLAPS (50) overlapping launches to exercise the
#      concurrent-writer race.
#   4. After every run: exit code must be 0 and every *.json in the container
#      must parse. At the end: no *.tmp.* leftovers.
#   5. Restores the backups and re-bootstraps the legacy agents (trap, so Ctrl-C
#      is safe).
#
# Env: SOAK_FULL, SOAK_PROCESSES, SOAK_OVERLAPS to override the counts.

set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
AGENT="$ROOT/native/build.noindex/Build/Products/Release/DeckAgent"
CONTAINER="$HOME/Library/Containers/com.deck.app.widgets/Data/Library/Application Support/Deck"
FULL="${SOAK_FULL:-200}"
PROCESSES="${SOAK_PROCESSES:-200}"
OVERLAPS="${SOAK_OVERLAPS:-50}"

failures=0
runs=0
overlaps_run=0

# --- build the agent if the Release build is missing ---------------------------
if [[ ! -x "$AGENT" ]]; then
  echo "building Release DeckAgent…"
  (cd "$ROOT/native" && xcodegen generate --spec project.yml >/dev/null && \
   xcodebuild -project Deck.xcodeproj -scheme DeckApp -configuration Release \
     -derivedDataPath build.noindex CODE_SIGNING_ALLOWED=NO build >/dev/null) || {
    echo "soak: build failed" >&2
    exit 1
  }
fi

# --- run one agent invocation and verify exit + container JSON -----------------
run_agent() {
  local outcome
  if ! "$AGENT" "$@" >/dev/null 2>&1; then
    failures=$((failures + 1))
    echo "soak: FAIL — $AGENT $* exited $?"
    return 1
  fi
  for f in "$CONTAINER"/*.json; do
    [[ -f "$f" ]] || continue
    if ! python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$f" 2>/dev/null; then
      failures=$((failures + 1))
      echo "soak: FAIL — corrupt JSON in $(basename "$f") after: $*"
    fi
  done
  runs=$((runs + 1))
  return 0
}

# --- isolate from the installed agents + user data ------------------------------
# Two worlds: installs predating SMAppService keep their LaunchAgents in
# ~/Library/LaunchAgents (boot out + re-bootstrap around the soak); installs
# since then register the agents via SMAppService from the signed bundle, and
# those jobs cannot be re-bootstrapped by this script — so the soak leaves
# them running and relies on the parse-only checks tolerating concurrency
# (atomic snapshot writes).
LEGACY_PLIST="$HOME/Library/LaunchAgents/com.deck.agent.plist"
if [[ -f "$LEGACY_PLIST" ]]; then
  launchctl bootout "gui/$(id -u)" "$LEGACY_PLIST" 2>/dev/null || true
  launchctl bootout "gui/$(id -u)" "$HOME/Library/LaunchAgents/com.deck.agent.processes.plist" 2>/dev/null || true
fi

BACKUP="$(mktemp -d)"
if [[ -d "$CONTAINER" ]]; then
  cp -a "$CONTAINER" "$BACKUP/container"
else
  mkdir -p "$CONTAINER"
fi

cleanup() {
  if [[ -d "$BACKUP/container" ]]; then
    rm -rf "$CONTAINER"
    cp -a "$BACKUP/container" "$CONTAINER"
  fi
  if [[ -f "$LEGACY_PLIST" ]]; then
    launchctl bootstrap "gui/$(id -u)" "$LEGACY_PLIST" 2>/dev/null || true
    launchctl bootstrap "gui/$(id -u)" "$HOME/Library/LaunchAgents/com.deck.agent.processes.plist" 2>/dev/null || true
  else
    echo "soak: SMAppService agents were left running; nothing to restore"
  fi
  rm -rf "$BACKUP"
}
trap cleanup EXIT INT TERM

# --- throwaway settings fixture (never touches the real settings) --------------
cat > "$CONTAINER/settings.json" <<'EOF'
{"homebox":{"location":"Paris"}}
EOF

echo "soak: ${FULL} full runs + ${PROCESSES} process runs + ${OVERLAPS} overlaps"

# --- main loops -----------------------------------------------------------------
for i in $(seq 1 "$FULL"); do
  run_agent
done
for i in $(seq 1 "$PROCESSES"); do
  run_agent --processes
done
for i in $(seq 1 "$OVERLAPS"); do
  "$AGENT" >/dev/null 2>&1 &
  p1=$!
  "$AGENT" --processes >/dev/null 2>&1 &
  p2=$!
  wait "$p1"; ok1=$?
  wait "$p2"; ok2=$?
  if [[ $ok1 -ne 0 || $ok2 -ne 0 ]]; then
    failures=$((failures + 1))
    echo "soak: FAIL — overlapping launch $i exited $ok1/$ok2"
  else
    overlaps_run=$((overlaps_run + 1))
  fi
done

# --- leftover temp files ----------------------------------------------------------
leftovers="$(find "$CONTAINER" -name '*.tmp.*' 2>/dev/null)"
if [[ -n "$leftovers" ]]; then
  failures=$((failures + 1))
  echo "soak: FAIL — leftover temp files:"
  echo "$leftovers"
fi

echo "soak: $runs runs, $overlaps_run overlaps, $failures failures"
[[ $failures -eq 0 ]]

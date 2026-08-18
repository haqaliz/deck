# 24h crash/robustness soak — runbook

Closes the M4 milestone item ("run 24h, no leaks", `ROADMAP.md`). The CI-fast
proxy is `scripts/soak.sh` (400 runs + 50 overlapping launches); this runbook
is the wall-clock acceptance step, run on a real Mac with the signed app
installed.

## Setup (5 min)

1. Build + install the signed app (see README "Install").
2. `open /Applications/Deck.app` — first run installs the agents.
3. Right-click desktop → Edit Widgets… → add **all nine** widgets
   (LiveBox, OpenBox, NetBox, BatBox, GitBox, DevBox, ClipBox, HomeBox,
   ShipBox). **Leave them on screen** — WidgetKit throttles hidden widgets,
   so the soak only exercises what is visible.
4. Run the compressed soak once to prove the write paths:
   `scripts/soak.sh` → expect `0 failures`.
5. Record start time and `log show` baseline:
   `log show --last 10m --predicate 'subsystem == "com.deck.agent"' --info |
   grep -c "failed"` (count known pre-existing failures, if any).

## The 24h run

- Leave the Mac awake (or use `caffeinate -d -t 86400`) with the widgets
  visible for 24 hours.
- **Every hour** (or every 4h if you trust the trend, more often overnight
  is not needed) run:

```bash
log show --last 1h --predicate 'subsystem == "com.deck.agent"' --info \
  | grep -E "failed (opencode|processes|gitbox|devbox|clipbox|weather|shipbox) snapshot"
```

Expected: no `failed` lines except `weather` while offline — a weather
failure is a *skip*, not a crash (the agent continues and logs `written`
for the rest). Any repeated non-weather `failed` line, any `crash` lines, or
a stuck widget (stale timestamps, blank face, no re-render for > 2 refresh
cycles) is a failure — collect:

- `log show --last 30m --predicate 'subsystem == "com.deck.agent"' --info`
- `log show --last 30m --predicate 'process == "DeckWidgets"'`
- a screenshot of the affected widget.

## Memory check (no leaks)

The extension is a transient process, so check it while it refreshes:

```bash
leaks $(pgrep -f DeckWidgets.appex | head -1)
```

Do this a few times across the run (each check is a fresh render cycle —
repeatable growth is the leak signal, not a one-off blip). Also keep an eye
on Activity Monitor: DeckWidgets memory should stay flat across hours, and
DeckAgent should stay near zero (it exits after every tick).

## Done

- If nothing surfaced: note it in the PR body — "24h soak passed:
  N widgets visible, no failed snapshots, no crashes, memory flat"
  (verification note, not a merge gate — CI already proves no-crash +
  valid files via `scripts/soak.sh`).
- If something surfaced: file a follow-up (new bug slug) with the collected
  logs before closing this unit.

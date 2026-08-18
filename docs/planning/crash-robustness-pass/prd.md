# PRD: crash-robustness-pass

**Slug:** `crash-robustness-pass` (branch `chore/crash-robustness-pass/aliz`)
**Type:** chore · **Source:** `docs/planning/_card/issue.md` (deck-next handoff)
**Date:** 2026-08-18

## 1. Restate the ask

Close the last open M4 milestone (`ROADMAP.md:51`, "run 24h, no leaks") by
hardening the known crash/corruption surface in the write paths, adding crash
triage diagnostics, and proving stability with a compressed soak harness plus
a documented manual 24h run. This is an infrastructure pass — it must not
change any widget's front face or the shell invariants.

## 2. What the user notices

Nothing at a glance — the point is that nothing *breaks*:

- No truncated/corrupt `*.json` snapshots after a crash or a race between the
  two agents (today a mid-write kill can leave `processes.json` unreadable
  until the next write).
- Snapshot files remain valid JSON even when the full agent (60s) and the
  `--processes` agent (15s) fire in the same instant.
- A 24h run leaves no memory growth in the extension and no agent error spam;
  failures are visible in OSLog (`log show --predicate 'subsystem ==
  "com.deck.agent"'`) instead of silent.

## 3. Surface addressed (the crash/corruption map)

All findings below are from the Phase-2 dig; every claim cites a file:

| # | Finding | File | Severity |
|---|---|---|---|
| F1 | Full agent and `--processes` agent both write `processes.json`, non-atomically | `DeckAgent/main.swift:48` and `:24-27`; `Shared/ProcessSnapshot.swift:43` | High — concurrent-writer race can corrupt the file both agents read |
| F2 | All 7 snapshot stores write non-atomically (`try? data.write(to:)`) | `Shared/{ProcessSnapshot,OpenCodeSnapshot,GitBoxSnapshot,DevBoxSnapshot,ClipBoxSnapshot,HomeBoxSnapshot,ShipBoxSnapshot}.swift` | Medium — truncated file on crash/power-loss; widget degrades to empty until next write |
| F3 | LiveBox `HistoryStore` writes non-atomically | `DeckWidgets/LiveBoxWidget.swift:42-49` | Medium — corrupt `history.json` silently resets the chart |
| F4 | App host also writes DevBox/ClipBox/HomeBox/ShipBox snapshots concurrently with the agent | `DeckApp/DeckApp.swift:133-168` | Medium — same race as F1 on those files |
| F5 | Force unwraps in `RemoteOpenCodeLoader` | `Shared/RemoteOpenCodeLoader.swift:304` (guarded by `contains(where:)`) and `:320` (key exists in iteration) | Low — safe today, flagged as the only `!` in production code |
| F6 | No agent-side run logging — failures are silent | `DeckAgent/main.swift` (no OSLog calls) | Low — triage blind spot for the 24h run |

Already robust (verified, no work): widgets render a graceful "unavailable"
state on nil/stale snapshots (`DeckWidgets/OpenBoxWidget.swift:89-107`),
settings tolerant-decode per field (`Shared/DeckSettings.swift`), and widget
index math is guarded (`max`/`min`/`prefix` throughout).

## 4. Spec (resolved in interview + critique)

1. **Atomic writes (F2, F3, F4):** every snapshot store + `HistoryStore` writes
   to a temp file **with a unique name in the same directory**
   (`<name>.json.tmp.<UUID>`), then `FileManager.replaceItemAt` over the
   target. Unique temp names keep concurrent app+agent renames benign (last
   rename wins; the target is always a complete file). Reuse one shared helper
   in `Shared/` (pure, testable). If `replaceItemAt` throws, fall back to
   `data.write(to: .atomic)` — never crash, never drop the data silently.
2. **Single writer for `processes.json` (F1):** the full agent stops writing
   the process snapshot; `--processes` (fast agent) is the sole writer. Full
   agent keeps everything else. Coupling note: both agents are installed and
   removed together by the app (`DeckApp/DeckApp.swift:194-204`), so the
   dependency is safe; the harness must cover a run where the fast agent is
   active (its 15s plist is what gates freshness).
3. **App host keeps its writers (F4):** the app may still write DevBox/ClipBox/
   HomeBox/ShipBox snapshots, but now atomically — same unique-temp+rename
   helper, so concurrent agent+app writes can't corrupt.
4. **Agent OSLog (F6):** `DeckAgent` logs per snapshot: written / skipped /
   failed (OSLog subsystem `com.deck.agent`). Never log server URLs, tokens,
   paths, or repo names — only the snapshot name and outcome.
5. **Soak harness (acceptance):** `scripts/soak.sh` builds Release, writes a
   throwaway `settings.json` fixture (fixed weather location, **no** ShipBox
   repo/token, **no** OpenBox server/token → those paths skip or fail without
   touching the network), then runs the agent binary in both modes in a tight
   loop (≥ 200 full runs + ≥ 200 `--processes` runs, including overlapping
   launches to exercise the race), asserting exit 0 every run and valid JSON
   for every snapshot file after every run. Network failure (weather) must be
   a *skipped* snapshot, never a crash — the harness asserts exactly that.
   Fast enough for CI (minutes, not hours).
6. **Manual 24h:** documented runbook (widgets added and left visible; agent
   logs checked via `log show --predicate 'subsystem == "com.deck.agent"'`;
   memory checked via `leaks`/Activity Monitor; widgets re-render without
   gaps). Honest boundary: **CI cannot prove "no leaks"** — the extension is
   a transient process, so the widget-side leak check is the manual 24h step
   only. CI proves: no crash under load, valid files, benign races. The PR is
   merged with the harness green; the 24h run is a verification note in the
   PR body, not a gate.

## 5. Shell fit

- **No shell invariant touched**: no widget front/back face changes, no
  settings, no cadence changes (60s floor untouched), no data-path switch.
- Files touched: `native/Shared/*` (store helpers + the 7 stores),
  `native/DeckWidgets/LiveBoxWidget.swift` (HistoryStore), `native/DeckAgent/
  main.swift`, new `native/Shared/AtomicStore.swift`-style helper,
  new `scripts/soak.sh`, `docs/` (runbook), README/ROADMAP registration.
- TDD: atomic-write helper + store behavior tested in `DeckSharedTests`
  (existing target, `native/SharedTests/`); harness assertions shell-tested.

## 6. Non-goals

- No GPU/ANE/thermal (documented blocker: `docs/planning/livebox-per-core-cpu/
  prd.md:94`) — explicitly excluded by the brief.
- No new snapshots, no new widgets, no settings UI, no cadence changes.
- No watchdog/restart logic — launchd `StartInterval` already re-fires the
  agent; a crash is not a stuck loop.
- No rewrite of `RemoteOpenCodeLoader` (F5 stays as a noted-low-risk item; a
  defensive `??` tweak is allowed only if it comes with a test).

## 7. Open questions

None — resolved in the interview (harness + manual 24h; atomic + single
writer; OSLog diagnostics).

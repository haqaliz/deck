# Deck Roadmap

Small, beautiful macOS desktop widgets that behave like native ones. The
product value is **one WidgetKit extension** (five widgets in the Widget
Center) plus **one metric story per widget**. New widgets reuse the widget
shell and only add a data source + a layout.

## The widget blueprint (how to add a widget)

1. **Copy a widget**: `native/DeckWidgets/<Widget>Widget.swift` (start from
   GitBox or NetBox) + register it in `DeckWidgets/DeckWidgets.swift`.
2. **Data source**: sandbox-safe loaders (mach, getifaddrs, IOKit) run inside
   the widget; anything else (subprocesses, other apps' data) goes through the
   agent: add a snapshot model + store in `native/Shared/`, sample it in
   `DeckAgent/main.swift`, render from the store in the widget.
3. **Settings**: add a `<Widget>Settings` struct to `Shared/DeckSettings.swift`
   and a tab in `DeckApp/DeckApp.swift`. Settings live in the app only.
4. **Register**: README.md, ROADMAP.md, `DeckWidgets/DeckWidgets.swift`.
5. **Verify**: build + install, re-add from the gallery, check all three sizes.
6. **Plan artifacts**: `docs/planning/{slug}/prd.md` → `plan_*.md` via the
   `deck-prd` / `deck-plan` skills. Pick the next item with `deck-next`.

## Milestones

### M1 — Foundation (DONE)
- [x] LiveBox (CPU/MEM/DISK chart + top processes, CPU/MEM tabs)
- [x] OpenBox (opencode tokens: in/out/cost, 14-day chart, top models parsed)
- [x] Native WidgetKit project building with automatic signing
- [x] Repo: deck, CLAUDE.md, skills, README

### M2 — Native Deck (DONE)
- [x] Deck app + extension registered in the Widget Center (`pluginkit`)
- [x] All five widgets in one bundle, small/medium/large sizes
- [x] Agent pump (`DeckAgent` CLI + LaunchAgent): opencode snapshot, process
      list, git snapshot — silent, embedded in Deck.app
- [x] Settings window in Deck.app (tabs per widget, colors, counts, token/URL,
      repo paths) applied to widgets instantly
- [x] OpenBox remote server mode (token + URL → HTTP metrics)
- [x] Non-native window widgets removed — Widget Center is the only surface

### M3 — More widgets (candidates, pick via deck-next)
- [x] **NetBox** — network: up/down rates + history, interfaces
- [x] **BatBox** — battery: level, time remaining, charge state
- [x] **GitBox** — git activity: today + streak, 14-day chart, active repos
- [x] **DevBox** — open ports/processes, Docker containers (docker stats)
- [x] **ClipBox** — clipboard history with previews (local only)
- [x] **HomeBox** — weather + timezones (wttr.in)
- [x] **ShipBox** — build/deploy status: GitHub Actions runs for a repo

### M4 — Polish
- [ ] Crash/robustness pass: run 24h, no leaks
- [x] Settings schema migration (tolerant decode for all settings structs)
- [x] Tests: XCTest target for the Shared parsers (GitLogParser, ModelParser,
      formatters, DB SQL) — `DeckSharedTests`, runs on CI
- [ ] Share the agent data path for LiveBox processes on a tighter cadence

Deferred from the tests milestone (still untested, pick via deck-next):
- DevBox parsers (`DevBoxSnapshot` lsof/docker), RemoteOpenCodeLoader
  aggregation, ProcessSnapshot parsing, and the remaining Loader formatters
  (BatteryMetrics, SystemMetrics per-core math — the latter needs the per-core
  math moved to Shared first). NetworkMetrics.formatRate is covered since the
  loader moved to `Shared/NetBoxCore.swift`.

## Feature backlog (existing widgets)

LiveBox:
- [x] Per-core CPU lines (first 8 cores) or per-core selection
- [ ] Apple Silicon GPU/ANE usage, thermal state
- [ ] Disk per-volume (multiple mounts)
- [x] Threshold coloring (amber/red when a value crosses warn/alarm thresholds)

OpenBox:
- [x] Cost-per-day chart (stacked by model)
- [x] Session list (top sessions by tokens, large face) — "drill-down" is the
      list itself; WidgetKit has no in-widget navigation, so tap-through is
      out of scope
- [x] Tool usage stats (bash/edit/read counts from the DB)

NetBox:
- [x] Network interface picker (manual override of the auto "most active" pick)
- [x] Per-interface packet counts / error counters
- [x] Threshold coloring on rates

## Planning workflow

- **Pick** the next widget/feature: `deck-next` (reads this file + docs/planning).
- **Plan**: `deck-begin-fast <slug>` → PRD (`deck-prd`) → plan (`deck-plan`) → implement.
- Artifacts live in `docs/planning/{slug}/`; deferrals must record the blocker.

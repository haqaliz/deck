# Deck Roadmap

Small, beautiful macOS desktop widgets that behave like native ones. The
product value is the **shared shell** (one proven window/card/flip/settings
pattern) plus **one metric story per widget**. New widgets reuse the shell and
only add a data source + a layout.

## The widget blueprint (how to add a widget)

1. **Copy the shell**: `Sources/<Widget>/` with AppMain, Settings, SettingsStore,
   MetricsStore, ContentView, SettingsView (start from LiveBox; keep the panel
   invariants in CLAUDE.md).
2. **Data source**: a pure loader (mach APIs, `ps`, sqlite via `opencode db`,
   HTTP, etc.) returning plain structs. No timers in the loader.
3. **UI**: front face = header metrics + chart/list; back face = settings
   (toggles pinned right, color pickers). Card style must match the shell.
4. **Register**: README.md, ROADMAP.md, `Package.swift` executableTarget.
5. **Verify**: `swift build -c release`, `swift run <Widget> --debug-flip`,
   check window bounds = content height, corners rounded, sits behind windows.
6. **Plan artifacts**: `docs/planning/{slug}/prd.md` → `plan_*.md` via the
   `deck-prd` / `deck-plan` skills. Pick the next item with `deck-next`.

## Milestones

### M1 — Foundation (DONE)
- [x] LiveBox (CPU/MEM/DISK chart + top processes, tabs CPU/MEM, up to 20, scroll)
- [x] OpenBox (opencode tokens: in/out/cost, 14-day chart, top models parsed from JSON)
- [x] Shared shell: material card, rounded window mask, flip settings, dynamic height,
      behind-windows level, drag, right-click close, launch-at-login (LaunchAgent),
      native-widget detection
- [x] `native/` WidgetKit project (builds; needs Apple signing to register)
- [x] Repo: deck, CLAUDE.md, skills, README

### M2 — Polish & installability
- [ ] Native widget signed + installable (document Xcode team step; verify `pluginkit`)
- [ ] Launch at login for both widgets verified end-to-end
- [x] OpenBox remote server mode (token + URL → HTTP metrics instead of local DB)
- [ ] Crash/robustness pass: run 24h, no leaks, settings schema migration
- [ ] Tests: add an XCTest target for metrics parsing (ModelParser, formatters, DB SQL)

### M3 — More widgets (candidates, pick via deck-next)
- [x] **NetBox** — network: up/down speed + history, current interfaces (en0…)
- [x] **BatBox** — battery: level, time remaining, cycle count, charge history
  (history is self-sampled from launch — no system battery-history API)
- [x] **GitBox** — today's git activity: today count + streak, 14-day commit
  chart, active repos list (git log across configured paths, default ~/dev)
- [ ] **DevBox** — open ports/processes, Docker containers (docker stats)
- [ ] **HomeBox** — weather + timezones (wttr.in), always-on
- [ ] **ClipBox** — clipboard history with previews (local only)
- [ ] **ShipBox** — build/deploy status: GitHub Actions runs for a repo

### M4 — Shell as a library
- [ ] Extract the shell into a reusable SPM library (`DeckCore`): panel setup,
      settings store, flip card, dynamic height — widgets become ~100 lines each
- [ ] Widget templates (Xcode template or `deck new <Widget>` script)

### M5 — Native parity
- [ ] WidgetKit widget for OpenBox (gallery + desktop)
- [ ] Shared data source package between window widgets and WidgetKit widgets

## Feature backlog (existing widgets)

LiveBox:
- [ ] Per-core CPU lines or per-core selection
- [ ] Apple Silicon GPU/ANE usage, thermal state
- [ ] Disk per-volume (multiple mounts), network interface picker
- [ ] Threshold coloring (e.g. red when CPU > 90%)

OpenBox:
- [ ] Cost-per-day chart (stacked by model)
- [ ] Session list with drill-down (top sessions by tokens)
- [ ] Tool usage stats (bash/edit/read counts from the DB)

NetBox:
- [ ] Network interface picker (manual override of the auto "most active" pick)
- [ ] Per-interface packet counts / error counters
- [ ] Threshold coloring on rates

## Planning workflow

- **Pick** the next widget/feature: `deck-next` (reads this file + docs/planning).
- **Plan**: `deck-begin-fast <slug>` → PRD (`deck-prd`) → plan (`deck-plan`) → implement.
- Artifacts live in `docs/planning/{slug}/`; deferrals must record the blocker.

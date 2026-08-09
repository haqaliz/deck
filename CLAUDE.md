# Deck: Project Context

This file orients an agent working in this repository. Read it first. Deeper
context lives in `ROADMAP.md` and `docs/planning/`.

## What this project is

**Deck** is a collection of small, beautiful macOS desktop widgets — floating
glass cards with native material look that sit **behind** app windows, like
native desktop widgets. Each widget is a card you can flip to configure.

- **LiveBox** — system monitor: live CPU / MEM / DISK chart + top processes.
- **OpenBox** — opencode usage: today's in/out tokens + cost, 14-day chart,
  top models (parsed from the opencode DB).

Plus a WidgetKit extension (`native/`) for a true system widget.

## Architecture — the widget shell (read before touching any widget)

Every widget follows the same shell. New widgets copy the shell; the shell is
the product's value. Files per widget under `Sources/<Widget>/`:

```
AppMain.swift        # @main: borderless NSPanel, level .normal (behind windows),
                     #   material card, flip, drag, --corner/--margin/--click-through
Settings.swift       # Codable settings struct + SettingsStore (JSON in
                     #   ~/Library/Application Support/<Widget>/settings.json)
SettingsView.swift   # the flip-card back face (toggles pinned right, color pickers)
MetricsStore.swift   # ObservableObject, 1s-ish Timer polling a loader
Metrics/OpenCodeMetrics.swift  # data loaders (mach APIs, ps, opencode db)
ContentView.swift    # front face (header + chart + list) + back face (settings) + flip
```

**Panel invariants — do not break:**

- `panel.level = .normal` → widgets stay behind app windows.
- `hostingView.layer.cornerRadius = 22` + `masksToBounds` → the window clips to
  the rounded card; top padding ≥ 28 keeps content clear of the corner arc.
- Height is **dynamic**: the front face measures its content via a
  `PanelHeightKey` preference; `reportHeight()` drives both the content root
  frame (`panelHeight`) and `onHeightChange` → `setWidgetHeight`. The content
  root MUST carry `.frame(width: 368, height: panelHeight)` so the window's
  fitting size matches the window (macOS 26 snaps windows to fitting size).
  Do not reintroduce fixed fill frames or the circular-measurement bug.
- Card style: `.fill(.clear).background(.ultraThinMaterial).clipShape(RoundedRectangle(22)).overlay(hairline)` —
  material-as-background + explicit clip is the only pattern that renders
  rounded on macOS 26; `Shape.fill(Material)` renders square.

## Commands

```bash
swift build                      # build both widgets
swift build -c release           # release
swift run LiveBox                # system monitor (options: --corner tl|tr|bl|br, --margin, --click-through, --debug-flip, --debug-render)
swift run OpenBox                # opencode usage (defaults top-right)
```

- `--debug-flip` starts on the settings face (screenshot/debug).
- `--debug-render <path>` renders the settings face to a PNG (debug).

## Conventions

- Two widgets must stay visually identical in shell behavior (padding, corners,
  heights). When changing the shell, change both and diff the windows
  (`CGWindowList` bounds via `swift` one-liner).
- Metrics loaders return pure data; stores own timers; views own layout.
- The window widget and the native WidgetKit widget coexist; detect the native
  widget with `pluginkit -m -i com.livebox.app.widget` (see
  `NativeWidgetDetector`) to show/hide the window widget's startup/close affordances.
- New widgets: register in README.md and ROADMAP.md; add the target to
  `Package.swift` (executableTarget, path `Sources/<Widget>`).

## Native widget (`native/`)

xcodegen project (`project.yml`) → `LiveBox.xcodeproj`: LiveBoxApp (host) +
LiveBoxWidget (WidgetKit extension). Builds with `xcodebuild -project ... build`.
**Requires an Apple developer identity to register** (self-signed/ad-hoc is
rejected by `pluginkit`); document the Xcode signing step for installs.

## Roadmap

See `ROADMAP.md` for the widget pipeline, milestones, and how to pick the next
widget or feature. Planning artifacts live in `docs/planning/{slug}/`
(prd.md → plan_*.md), produced via the `deck-prd` / `deck-plan` skills.

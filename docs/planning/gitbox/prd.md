# GitBox — PRD

## Ask

Show today's git activity across the user's local repos in a deck widget:
header with today's commit count and current streak, a per-day commit bar chart
(14 days), and a per-repo list with commit counts. Slug: `gitbox`.

Source: `deck-next` handoff → `docs/planning/_card/issue.md` (ROADMAP.md:45).

## User-visible spec

### Front face (widget, 368pt card)

Header, then chart, then list — the NetBox layout:

1. **Header** — two labels, left-aligned, gear button right (shell pattern):
   - `TODAY` — number of commits made today (author date, local day).
   - `STREAK` — consecutive days with ≥1 commit. **Grace rule**: an empty today
     does not break the streak — count backwards from yesterday when today has
     no commits; a day with ≥1 commit extends the run.
2. **Chart** — bar chart, commits per day, last 14 days (today on the right).
   Bar color = settings; today's bar highlighted with a second color.
   Chart X axis hidden, no Y axis (or faint gridlines per shell style);
   height 130pt like NetBox's chart.
3. **List** — `REPOS` header + scrollable list of repos sorted by commits
   today (desc), up to N rows (settings, default 5, cap 10): repo short name
   (last path component) + today's commit count. Rows without commits today are
   omitted (the list is "who's active today").
4. **Empty state** — no repos found/configured (or all scans failed): one clean
   card line "No git repos found" + hint "Add paths in settings" (mirrors
   BatBox's no-battery empty state).

### Back face (settings, 358pt)

- **CHART** section: Show chart toggle (default on); bar color picker;
  today color picker.
- **REPOS** section:
  - Toggle "Show repos" (default on); repo count stepper (1–10, default 5).
  - **Scan depth stepper** (1–10, default 4) — recursive scan depth for the
    repo search.
  - **Paths list** — the configured repo paths (add via a small text field +
    Add button; remove via a per-row × button). A path may be a repo itself or
    a directory tree to scan (scan honours the depth setting).
- **REFRESH** section: refresh interval picker 10/30/60s (default 30s).
- **STARTUP** section: "Open at startup" toggle (LaunchAgent, shell pattern) —
    hidden when the native widget is registered (NativeWidgetDetector).

## Data source

- **Local git**: for each discovered repo run
  `git -C <path> log --pretty=%ad --date=format-local:%Y-%m-%d --since=<n days>` via
  `Process` (the BatBox ioreg pattern, `Sources/BatBox/BatteryMetrics.swift:72`).
  `format-local` renders each commit's **author date** as the machine's local
  calendar day — timezone normalization for streak/chart falls out for free.
  Repos are discovered by walking configured paths for `.git` (file or dir —
  covers worktrees/submodules), to the configured depth.
- **Pure core**: `GitBoxCore` holds models + `GitLogParser` (day strings →
  per-day counts), `GitMath` (streak with grace rule, top repos), `GitFormatters`.
  All testable without subprocesses. The `Process` runner stays in the widget
  target (`GitMetrics.swift`), like `NetworkMetricsLoader`.
- **Refresh**: first sample immediately, then timer at the configured interval.
  Sampling runs on a background queue (N×git-log can reach 100–300ms with many
  repos; the store marshals results to MainActor). History is the 14 daily
  buckets — no 90-sample rolling buffer.
- **Unavailable**: git missing, a repo path invalid, or a repo with no commits →
  skip that repo, never crash. Zero usable repos → empty state.

## Shell fit

- New target reusing the proven shell wholesale, following BatBox's copy:
  `AppMain.swift`, `Settings.swift`, `SettingsStore.swift`, `MetricsStore.swift`,
  `ContentView.swift` (flip, PanelHeightKey dynamic height, 368pt width,
  material card style), `SettingsView.swift`, `NativeWidgetDetector.swift`.
- **No panel invariant is touched**: level `.normal`, 22pt corner mask, dynamic
  height via PanelHeightKey, material-as-background card style — all copied
  verbatim from NetBox.
- Registration: `Package.swift` (library `GitBoxCore` + executable `GitBox` +
  test target `GitBoxCoreTests`), `README.md`, `ROADMAP.md` (mark M3 GitBox
  shipped), `run.sh`/`stop.sh`/`run-all.sh`/`stop-all.sh`.
- One new settings control type: the paths list editor (text field + add,
  per-row remove). Contained to GitBox's SettingsView; shell files unchanged.

## Non-goals

- No GitHub/remote activity (ShipBox's job — ROADMAP.md:49, not local-first).
- No per-author or per-branch breakdown; per-repo counts use HEAD only.
- No push/pull state, no uncommitted-change awareness, no repo stats beyond
  commits (no lines changed, no files touched).
- No autoscan of arbitrary roots beyond configured paths (default `~/dev`).

## Decisions (resolved in interview)

- Streak: grace until day ends (empty today doesn't break the run).
- Scan depth: default 4, configurable 1–10 in settings.
- Refresh: 30s default, 10/30/60s setting.
- Commit date: author date (`%ad`).

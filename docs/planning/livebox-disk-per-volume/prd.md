# PRD: LiveBox disk per-volume

Slug: `livebox-disk-per-volume`

## 1. Ask

Give LiveBox a disk per-volume slice (ROADMAP.md:69, `[ ]`): enumerate real
local volumes and show each one's used-percent + free space as rows on the
large face, while small/medium faces keep the aggregate DISK row. Pure
self-sampled data — no agent, no snapshot, no history change.

## 2. User-visible spec

### Front face

- **Small / medium**: unchanged. The aggregate DISK metric row is the only disk
  surface (`showDisk` toggle governs it as today).
- **Large**: when the new `Show per-volume disk` toggle is on, the aggregate
  DISK row is **removed from the header HStack** (CPU/MEM stay) and per-volume
  rows render as a **vertical list between the chart and the processes
  section** (up to 5 rows):
  - Row layout: colored dot (the DISK color) + volume name + `xx%` + free space
    (e.g. `Macintosh HD  71%  195 GB free`). Matches the existing `metricRow`
    visual language — rounded system font, monospaced digits, colored dot.
  - Row order: used-percent descending, so the fullest volume is first.
  - The aggregate chart line stays (chart still plots the aggregate DISK
    history).
  - Volume count cap: 5 rows max (typical systems have 1–3), so a machine with
    many mounts can't overflow the face.
- **Threshold coloring**: applies to the aggregate CPU/MEM/DISK rows and chart
  lines only, as today. Per-volume values are never threshold-tinted (their
  story is capacity/free space, not load).

### Back face (Deck app settings, LiveBox tab → "Disk" section)

- `Toggle "Show per-volume disk"` — default **on**, disabled when `showDisk`
  is off. Reuses the existing DISK color; no new color/count controls.
- All new keys follow the `LiveBoxSettings` tolerant-decode `init(from:)`
  pattern (`native/Shared/DeckSettings.swift:100`).

## 3. Data source

- **Where**: self-sampled inside the widget (path 1 in CLAUDE.md). No agent,
  no sandbox change — LiveBox already reads Volume resource keys in-widget
  (`SystemMetrics.swift:126`).
- **How**: extend the loader with a volume sampler using
  `FileManager.mountedVolumeURLs(includingResourceValuesForKeys: [.volumeLocalizedNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey], options: [.skipHiddenVolumes])` — the same Volume API as the existing `diskUsagePercent()`.
- **Volume set** (per interview): real local volumes — internal + external +
  disk images — deduped by `.volumeIdentifierKey`, excluding:
  - the **read-only system volume** (mount `/` — Catalina+ splits the boot
    volume: `/` is the sealed system snapshot, `/System/Volumes/Data` is the
    real read-write boot volume and MUST stay as the "Macintosh HD" row),
    plus the non-boot system siblings `/System/Volumes/Preboot|VM|Update` and
    pseudo mounts `/dev`, `/private/var/vm`, `/home`, `/net`;
  - network and Time Machine mounts (`.volumeIsLocalKey` == false).
  - The boot Data volume is presented under its container name (strip the
    " - Data" suffix from `.volumeLocalizedNameKey`).
- **Cadence**: sampled on every 5s `TimelineView` tick alongside CPU/MEM/DISK
  (cheap — statfs-class calls). History/persistence: none — per-volume data is
  live-only; the history `Sample` struct (`LiveBoxWidget.swift:11`) is
  unchanged, so old history files stay compatible.
- **Empty / unavailable**: if the sampler returns nothing (no local volumes),
  fall back to the existing aggregate DISK row so the face is never blank.

## 4. Shell fit

- Reuses the LiveBox widget + settings tab + `LiveBoxSettings` entirely; only
  additions:
  - `Shared/LiveBoxDiskCore.swift` — pure models + logic (percent, formatter,
    volume-set filtering) so DeckSharedTests can compile it (the widget target
    can't be compiled into the test bundle, `project.yml` `DeckSharedTests`).
  - `SystemMetrics.swift` — one sampler function (I/O), feeding the pure core.
  - `LiveBoxWidget.swift` — large face renders per-volume rows instead of the
    DISK row when the toggle is on.
  - `DeckSettings.swift` + `DeckApp.swift` — one setting + one section.
- No panel/shell invariants touched (card, flip, settings window, agent,
  refresh cadence — all unchanged).

## 5. Non-goals

- No small/medium per-volume UI.
- No per-volume history or chart.
- No threshold coloring on per-volume values.
- No per-volume colors/count controls (toggle only, per interview).
- No agent involvement, no new snapshot model, no changes to processes.
- GPU/ANE/thermal stays out (documented blocker:
  `docs/planning/livebox-per-core-cpu/prd.md:94`).

## 6. Open questions

- Name edge cases: external/APFS volumes whose localized name is empty or
  already collides with the boot name — fall back to the mount path; last-wins
  suffix stripping is enough for the " - Data" case.
- Cap exactness: 5 rows vs. `processCount`-style stepper. Pinned at 5 for now;
  can become a stepper in a follow-on.

## 7. Verification

- DeckSharedTests: volume-percent math, free-space formatter, volume-set filter
  (dedupe system volume, drop Data/VM/network mounts) with injected fixtures,
  and tolerant decode of the new setting.
- `xcodebuild ... build` clean; install; re-add LiveBox from the Widget Center;
  check small/medium (aggregate only) and large (per-volume rows with the
  toggle on, aggregate row with it off) across all three sizes.
- Register in README.md and ROADMAP.md (flip ROADMAP.md:69 to `[x]`).
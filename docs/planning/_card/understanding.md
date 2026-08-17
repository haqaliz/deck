# Understanding: livebox-disk-per-volume

## What the work is really asking

Give LiveBox a disk per-volume slice: enumerate mounted volumes and show each
volume's used-percent + free space as rows/bars, while small/medium faces keep
the aggregate DISK row. This is the deck-next pick for ROADMAP.md:69 (`Disk
per-volume (multiple mounts)`, `[ ]`). It must be **pure self-sampled data** —
LiveBox already samples mach/Volume in-process (`LiveBoxWidget.swift:61-99`),
so there is no agent, no snapshot, no process-list change, and the history
`Sample` struct (`LiveBoxWidget.swift:11-17`) stays untouched (per-volume data
is live-sampled, never charted over history). The volume math must live in a
**shared, testable core** (`LiveBoxCore.swift` precedent) so DeckSharedTests
can compile it — the widget target can't be compiled into a unit-test bundle
(project.yml `DeckSharedTests` compiles `Shared` + `SharedTests` only).

## Code map

- `native/DeckWidgets/Loaders/SystemMetrics.swift:126-135` — `diskUsagePercent()`
  reads only `/` via `URL.resourceValues([.volumeTotalCapacityKey,
  .volumeAvailableCapacityForImportantUsageKey])`. This is the I/O seam to
  extend: enumerate all volumes with the same Volume resource keys.
- `native/DeckWidgets/LiveBoxWidget.swift` — `LiveBoxSampler.sample()` (:65)
  returns `(cpu, mem, disk, perCore)` on every 5s `TimelineView` tick (:190);
  faces at :236 (small), :252 (medium), :275 (large); `metricRow` (:409) is the
  colored-dot row to reuse for per-volume rows.
- `native/Shared/DeckSettings.swift:79-116` — `LiveBoxSettings` with the
  tolerant-decode `init(from:)` pattern (:100-115); new keys must follow it.
- `native/DeckApp/DeckApp.swift:303-343` — `LiveBoxSettingsView`: Form with
  Chart/Metrics/Thresholds/Processes sections; add a Disk section.
- `native/Shared/LiveBoxCore.swift` — the shared pure-logic precedent
  (ThresholdTier); `NetBoxCore.swift` shows the Darwin-import pattern works in
  Shared (`import Darwin` + Foundation, compiles into DeckSharedTests).
- `native/SharedTests/` — XCTest suites; `DecodeTests.swift:143` covers
  `LiveBoxSettings` tolerant decode; new suite file for the volume core.

## Design sketch

- New `Shared/LiveBoxDiskCore.swift`: `struct VolumeInfo { name, mountPoint,
  totalBytes, availableBytes }`, pure `percentUsed(total:available:)`,
  `formattedFree` byte formatter, and `displayableVolumes(_:)` that drops
  pseudo/read-only/system duplicates. The I/O sampler (`volumeSamples()`, in
  `SystemMetrics.swift`) wraps `FileManager.mountedVolumeURLs(
  includingResourceValuesForKeys:options:)` (same Volume API as the current
  `diskUsagePercent()`) and feeds the pure core.
- `LiveBoxSettings`: `showPerVolumeDisk = true` (+ optional
  `perVolumeCount`/color), tolerant decode.
- `LiveBoxFace` large: per-volume rows (dot + name + `xx%` + free bytes),
  small/medium unchanged (aggregate DISK row only). Layout vs. the existing
  chart/processes blocks is an open question.

## Ambiguities for the interview

1. **Volume set**: which mounts count? Exclude `/System/Volumes/Data` and the
   read-only system volume; include external volumes? Dedupe by
   `.volumeIdentifierKey`? Network/Time Machine mounts excluded?
2. **Large-face layout**: per-volume rows replace the DISK chart line, sit
   below it, or only show when enabled? Keep the aggregate DISK row on large?
3. **Settings scope**: toggle only, or toggle + max volume count + per-volume
   color?
4. **Row content**: percent only, or percent + free bytes ("512 GB free")?
   Threshold coloring on per-volume values (likely no — thresholds are the
   aggregate's story)?
5. **Sampling cost**: enumerating volumes every 5s tick is cheap (statfs), but
   confirm no first-launch hiccup when external drives are spinning up.

## No shell invariants broken

No card/flip/settings-window/agent behavior changes; the only production edits
are one Shared core + one settings struct + one view section + loader I/O. Same
data path (self-sampled, path 1 in CLAUDE.md).
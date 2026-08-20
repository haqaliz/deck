# Understanding — livebox-thermal-state

## What the work is really asking

Add a fourth, non-percentage metric to LiveBox: the system thermal pressure
level from `ProcessInfo.processInfo.thermalState`. It closes the *shippable
half* of `ROADMAP.md:79` ("Apple Silicon GPU/ANE usage, thermal state") — GPU
and ANE stay blocked for lack of a public API
(`docs/planning/livebox-per-core-cpu/prd.md:94`).

**Verified on this machine (2026-08-20):** a 3-line Swift script printed
`raw: 1` → `.fair`. So the API resolves outside a widget, and the value is not
pinned at `.nominal` — the row shows real variation.

## Shell invariants this must respect (CLAUDE.md)

- **Path 1, self-sampled**: mach/IOKit-class data read *inside* the widget.
  `ProcessInfo` is sandbox-safe → **no DeckAgent, no snapshot JSON, no
  LaunchAgent, no entitlement change**.
- **60s timeline floor + `processRefreshInterval` tick**: unchanged. The
  sampler already runs per tick inside `TimelineView` (LiveBoxWidget.swift:196);
  thermal is one more read in that same tick.
- **Visual language**: rounded system fonts, monospaced digits, colored-dot
  metric rows, hidden chart axes.
- **Settings live in the app only**, with tolerant decode.

## Affected files

| File | Change |
|---|---|
| `native/Shared/LiveBoxCore.swift` (or a new `LiveBoxThermalCore.swift`) | pure level → tier + label mapping |
| `native/Shared/DeckSettings.swift:75-170` | `showThermal` field + `CodingKeys` + `decodeIfPresent` + `encode` |
| `native/DeckWidgets/LiveBoxWidget.swift` | sample thermal; render the row on the faces |
| `native/DeckApp/DeckApp.swift:337` (Metrics section) | the toggle |
| `native/SharedTests/` | new thermal tests + a `DecodeTests` case |
| `README.md`, `ROADMAP.md` | register; split line 79 |

## Precedent to copy

- Tint: `ThresholdTier.warnColor` / `.alarmColor` (`LiveBoxCore.swift:24-25`),
  applied via `tierColor()` (`LiveBoxWidget.swift:471`), gated on
  `showThresholdColors`.
- Tolerant decode + one-way key migration: `DeckSettings.swift:115-170`.
- Pure-logic-in-Shared-so-it-tests: `LiveBoxThresholdTier`, covered by
  `SharedTests/LiveBoxThresholdTests.swift`.

## Ambiguities for the interview

1. **Thermal is not a percent.** Every existing row is `%3.0f%%`
   (`LiveBoxWidget.swift:463`). A word ("Fair") in a numeric row is a new row
   shape — needs a decision, not an assumption.
2. **Which faces?** The medium/large header is a single `HStack` of CPU/MEM/DISK
   (LiveBoxWidget.swift:262-273); a fourth item risks crowding at medium.
3. **Chart or not?** The chart is `chartYScale(domain: 0...100)`; a 0–3 enum
   does not belong on that axis without rescaling.
4. **Tint mapping**: serious → warn, critical → alarm; nominal/fair untinted
   (mirrors "idle values are never tinted" from netbox-threshold-coloring).
   Should it obey `showThresholdColors`?
5. **Default on or off?** Precedent is split: `showPerCoreCores = false`,
   `showPerVolumeDisk = true`. A new row on the small face changes an existing
   layout for current users.

## No invariant is broken

Self-sampled, no new process, no cadence change, no new entitlement, no
settings UI inside the widget.

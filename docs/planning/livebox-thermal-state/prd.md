# PRD — LiveBox thermal state

**Slug:** `livebox-thermal-state` · **Type:** feat · **Branch:** `feat/livebox-thermal-state/aliz`

## 1. The ask

Add a fourth LiveBox metric row showing the system's **thermal pressure level**
(`ProcessInfo.processInfo.thermalState`), tinted with the shipped warn/alarm
language, so a glance at LiveBox says whether the machine is being thermally
throttled.

This closes the shippable half of `ROADMAP.md:79`. **GPU/ANE stays open and
blocked** — no public Apple Silicon API
(`docs/planning/livebox-per-core-cpu/prd.md:94`).

## 2. User-visible spec

### Front face — all three sizes

A metric row in the existing shape: colored dot + label `THRM` + the level word
uppercased (`NOMINAL` / `FAIR` / `SERIOUS` / `CRITICAL`).

```
SMALL                    MEDIUM / LARGE header
● CPU   45%              ● CPU 45%  ● MEM 60%  ● DISK 30%  ● THRM FAIR
● MEM   60%
● DISK  30%
● THRM  FAIR
```

- **Position:** last, after DISK — small as a 4th stacked row, medium/large as a
  4th item in the header `HStack` (LiveBoxWidget.swift:262-273, 285-296).
- **Tint:** `SERIOUS` → warn amber (`ThresholdTier.warnColor`), `CRITICAL` →
  alarm red (`.alarmColor`). `NOMINAL` and `FAIR` are **never tinted** — the
  "idle values are never tinted" rule from netbox-threshold-coloring.
- **Dot color:** the tier color when tinted, otherwise `.secondary`. **No new
  color-picker setting** — thermal has no user-chosen hue, unlike CPU/MEM/DISK.
- **Tint gate:** obeys the existing `showThresholdColors` toggle. With it off,
  the row renders plain (grey dot, primary text) but still shows the word.
- **Width mitigation (medium):** four items plus the 8-character `CRITICAL` is
  the widest case. Reduce the header `HStack` spacing from 14 to 10 when the
  thermal row is visible, and add `.lineLimit(1)` +
  `.minimumScaleFactor(0.75)`. Acceptance is measured, not assumed (§7).

### Back face — settings (Deck app → LiveBox tab, "Metrics" section)

| Control | Default | Notes |
|---|---|---|
| `Show thermal state` toggle | **off** | Opt-in, so existing LiveBox instances render byte-identically after the update (the `showPerCoreCores = false` precedent) |
| caption | — | "System thermal pressure (nominal / fair / serious / critical), not a temperature reading." |

No stepper, no color picker, no thresholds — the four levels *are* the scale.

## 3. Data source

- **`ProcessInfo.processInfo.thermalState`** — public Foundation API, works
  inside the sandboxed widget extension. **Path 1, self-sampled** (CLAUDE.md):
  no DeckAgent, no snapshot JSON, no LaunchAgent, no new entitlement.
- **Verified 2026-08-20** on this machine: a standalone Swift script printed
  `raw: 1` → `.fair`. The API resolves and is not pinned at `.nominal`.
- **Cadence:** read inside the existing `TimelineView` tick
  (`processRefreshInterval`, default 15s, LiveBoxWidget.swift:196). No new
  cadence, no change to the 60s timeline floor.
- **Unavailable state: none.** `ProcessInfo` always returns a value on every Mac
  (Intel included); there is no failure mode to render. Unknown future raw
  values are clamped (§4).

## 4. Shell fit

Reuses, without modification:

- `ThresholdTier.warnColor` / `.alarmColor` (`Shared/LiveBoxCore.swift:24-25`)
- the `tierColor()` gate pattern (`LiveBoxWidget.swift:471`)
- the tolerant-decode + explicit-`encode` shape (`Shared/DeckSettings.swift:115-170`)
- the pure-logic-in-`Shared`-so-it-tests rule (`LiveBoxThresholdTier`)

New pure core — `native/Shared/LiveBoxThermalCore.swift`:

```swift
enum ThermalLevel: Int { case nominal = 0, fair = 1, serious = 2, critical = 3 }

enum LiveBoxThermalCore {
    static func level(rawValue: Int) -> ThermalLevel   // < 0 → .nominal, > 3 → .critical
    static func label(_ level: ThermalLevel) -> String // "NOMINAL" … "CRITICAL"
    static func tier(_ level: ThermalLevel) -> ThresholdTier
}
```

Taking an `Int` rather than `ProcessInfo.ThermalState` keeps the mapping
testable in `DeckSharedTests` without fabricating a `ProcessInfo`; the widget
passes `ProcessInfo.processInfo.thermalState.rawValue`. A raw value above the
known range clamps to `.critical` (a state more severe than critical must not
degrade to "untinted"), below range to `.nominal`.

**Widget-side shape (specified so the percent rows stay untouched):**

- A **separate `thermalRow` view** — the existing
  `metricRow(metric:title:value:color:)` is percent-typed
  (`String(format: "%3.0f%%")`, LiveBoxWidget.swift:456-466) and cannot render
  a word.
- **Do not extend `LiveBoxMetric`** with a `.thermal` case: that enum feeds
  `LiveBoxThresholdTier`, which resolves a warn/alarm `Int` pair that thermal
  does not have. Thermal tiers come from `LiveBoxThermalCore.tier` instead.
- A **separate `LiveBoxSampler.thermal() -> ThermalLevel`**, not a fifth element
  in `sample()`'s tuple — that tuple flows into `history(appending:)` and
  `Sample`, which must stay untouched (§5).
- The **spacing change (14 → 10) is conditional on `settings.showThermal`** and
  applies to both the medium and large headers (they share the shape,
  LiveBoxWidget.swift:262 and :285) — so "off renders byte-identically" holds
  on both faces.
- `.lineLimit(1)` + `.minimumScaleFactor(0.75)` go on the **thermal `Text`
  only**, not the shared `HStack` — otherwise a long word would shrink the
  CPU/MEM/DISK percentages with it.

**No shell invariant is touched:** no new process, no cadence change, no
entitlement, no settings UI inside the widget, no chart/`Sample`/`history.json`
change.

## 5. Non-goals

- No temperature in degrees, no fan RPM, no per-sensor readings — those need
  private SMC access, which the sandbox refuses.
- No GPU/ANE usage (blocked, `livebox-per-core-cpu/prd.md:94`).
- No thermal line in the chart, no thermal history — the chart is
  `chartYScale(domain: 0...100)` and a 0–3 enum rescaled onto it would read as
  a fake percentage. `Sample` and `history.json` are untouched.
- No notifications, no throttling advice, no per-level color pickers.
- No `NSProcessInfoThermalStateDidChange` observer — polling on the existing
  tick is sufficient and avoids widget-lifecycle state.

## 6. Decisions (resolved in interview)

1. **Word row on all three faces** — consistency with the existing metric-row
   shape beats saving space on small.
2. **Default off** — no layout change for widgets the user has already placed.
3. **No chart** — see §5.

## 7. Acceptance criteria

- [ ] `LiveBoxThermalCore.level(rawValue:)` maps 0–3 and clamps out-of-range
      (`-1` → `.nominal`, `4` → `.critical`); unit-tested.
- [ ] `tier`: nominal → `.normal`, fair → `.normal`, serious → `.warn`,
      critical → `.alarm`; unit-tested.
- [ ] `label`: uppercase words; unit-tested.
- [ ] `{}` decodes to `showThermal == false`; `{"showThermal":true}` decodes
      true; round-trip encode emits the key; existing keys unaffected
      (DecodeTests).
- [ ] Toggle off → all three faces render byte-identically to master.
- [ ] Toggle on → the row appears last on all three sizes.
- [ ] Small face fits four rows without clipping (budget: 4 rows ≈ 15pt each +
      3 × 8pt spacing ≈ 84pt against ~130pt usable — expected to fit, but
      confirmed by eye, not by arithmetic).
- [ ] `showThresholdColors` off → thermal row never tinted.
- [ ] **Medium face at `CRITICAL` with CPU+MEM+DISK+THRM all shown does not
      truncate or clip** — verified by eye on the installed widget.
- [ ] Tinting verified at `SERIOUS` and `CRITICAL` by **temporarily hardcoding
      the level in `LiveBoxSampler.thermal()` in an uncommitted local build**,
      checking all three sizes, then reverting. macOS offers no supported way
      to force a thermal state (verified: `pmset -h` exposes no thermal option;
      `pmset -g therm` reports "No thermal warning level has been recorded"
      even while `ProcessInfo` reports `.fair`, so it is not a cross-check
      either). Sustained load may never reach `serious` on this machine.
- [ ] Build + install, re-add LiveBox from the gallery, all three sizes render.
- [ ] `README.md` LiveBox row + `ROADMAP.md:79` split into a shipped thermal
      line and a still-blocked GPU/ANE line.

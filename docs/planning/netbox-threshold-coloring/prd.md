# NetBox threshold coloring — PRD

Slug: `netbox-threshold-coloring`
Type: feature on a shipped widget (NetBox)
Source: `docs/planning/_card/issue.md` (inline brief from deck-next, picked
against ROADMAP.md:82 backlog `[ ]` "Threshold coloring on rates").

## 1. The ask

Give NetBox the same warn/alarm threshold coloring LiveBox shipped in
`8215d0f`: the UP/DOWN totals rows, the history chart lines, and the
per-interface rate values all turn amber/red when the resolved rates cross
user-configured thresholds — controlled by a "Thresholds" section in the NetBox
settings tab.

## 2. User-visible spec

### Front face (all three sizes)

- **Totals rows (DOWN / UP)**: the rate text turns amber at `warn`, red at
  `alarm`; the colored dot keeps the user's color. `0` rates (idle or no
  reading) keep the user's color — never tinted.
- **History chart (medium/large)**: each UP/DOWN point uses the same tier
  coloring per sample, exactly like LiveBox's per-point line coloring
  (`LiveBoxWidget.swift:364,376,387,398`).
- **INTERFACES list (medium/large)**: the `↑` and `↓` rate texts per interface
  are tinted per their own rate. Names and dots unchanged.

Thresholds apply to the **resolved** interface set — the same `pinned` set
`NetBoxProvider` already computes totals from (pin wins, auto-most-active
otherwise), so no new resolution logic is needed.

### Back face (Deck app → NetBox tab, new "Thresholds" section)

Mirroring `LiveBoxSettingsView` (DeckApp.swift:324-333):

- Toggle "Show threshold colors" — default **on**.
- Stepper "Warn at: X MB/s" — Int, range 1...2000, default **50**.
- Stepper "Alarm at: X MB/s" — Int, range 1...2000, default **100**.
- Caption: same wording as LiveBox's, adapted to MB/s.

Both steppers disabled while the toggle is off. LiveBox allows 0% thresholds;
NetBox floors steppers at 1 MB/s so a 0 can never mean "idle rates are an
alarm" (the `≤0 = no reading` guard plus the 1-floor keep idle from ever
tinting).

## 3. Data source

- Self-sampled, sandbox-safe (existing path): `NetworkMetricsLoader.sample()`
  (getifaddrs) → per-interface rates → resolved set → totals + history. No new
  data source, no agent involvement.
- Cadence unchanged: 60s timeline reload; rates need two byte-counter samples
  (persisted previous sample, `NetBox.previousSample`, 300s staleness cutoff).
- **Staleness/unavailable**: when the previous sample is stale (>300s) rates
  are `[]`, totals are 0 and the medium face shows "Sampling…". All `0`/negative
  rates (counter reset, `NetBoxCore.rate()` guard) map to `.normal` tier — no
  reading, never a false alarm. This is a deliberate deviation from raw
  `ThresholdTier.tier` semantics, which would alarm at `value >= alarm` even
  for 0 (e.g. if the user set alarm=1 MB/s).

## 4. Shell fit

- Reuses the existing NetBox widget shell entirely — no changes to panels,
  materials, sizes, or the containerBackground.
- `ThresholdTier` (Shared/LiveBoxCore.swift:10-26) was extracted precisely for
  this ("NetBox will reuse the same rules — ROADMAP.md:81" in its doc comment);
  it is NOT modified. A new NetBox-specific wrapper in `Shared/NetBoxCore.swift`
  adds the zero-guard + MB/s conversion so the policy is unit-testable in
  DeckSharedTests (widget target can't host tests).
- No CLAUDE.md invariant is touched.

## 5. Non-goals

- No per-direction threshold pairs (one warn/alarm pair covers UP and DOWN).
- No threshold coloring on the "ACTIVE" row or interface names/dots.
- No changes to rate math, staleness windows, or pinned-interface resolution.
- No widget-side settings UI (settings live in the Deck app only, per the
  architecture).

## 6. Open questions

None — resolved in interview:

1. Units: **MB/s, one pair for both directions** (defaults warn 50 / alarm 100).
2. Scope of tinting: **totals rows + chart + interface rows**.

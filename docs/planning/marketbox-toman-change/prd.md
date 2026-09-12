# PRD: MarketBox — the Toman rate's own 24h change

**Slug:** `marketbox-toman-change` · **Type:** feat · **Source:** inline brief
(deck-next handoff 2026-09-12, ROADMAP M8 #1) · **Date:** 2026-09-12

## 1. Restated ask

In IRR/IRT displays, the configured **USD fiat row's price is the free-market
Toman anchor** (1 USD in Toman, via Wallex). Wallex already reports that
anchor's 24h change and `WallexParser` already parses it — but the loader
throws it away and the row renders "–" instead of "+2.0%". Carry the change
through to that one row.

## 2. User-visible spec

**Front face** (medium/large, and small stays price-only):

- The USD row in an **IRT or IRR** display gains its day-change label —
  colored `upColor` / `downColor`, same as crypto and stock rows, gated by the
  existing **Show day change** toggle (default ON).
- A Wallex tick that lacks `24h_ch` renders "–" for that tick (no change, not
  a failure). Gold and every other fiat row stay "–" forever.
- The gallery placeholder gains a sample change on its USD row so the feature
  is visible in the preview.
- The small face is unchanged (price-only by design).

**Back face**: no new controls. The existing `showDayChange` toggle governs.

## 3. Data source

- **Source:** Wallex `USDTTMN.stats["24h_ch"]` — already fetched (same request,
  zero new calls), already parsed into `WallexRate.change24h`
  (`MarketBoxSnapshot.swift:139-141`), already fixture-tested
  (`WallexParserTests`, `wallexMarkets.json` carries `24h_ch: 2.02`).
- **Cadence:** the existing 60s agent tick. The change is captured at the same
  instant as the rate — same payload, so they can never disagree.
- **Unavailable:** rate present but `24h_ch` absent → `dayChangePct: nil` →
  "–". Wallex fetch fails → the USD row omits as today (partial-failure
  policy unchanged). A missing change can never fail a tick.

## 4. Shell fit

Pure follow-on slice, no shell touch:

- `MarketBoxSnapshot.swift` — `fetchToman()` returns `WallexRate` (rate still
  required; change optional) instead of `Double`; `HostMarketLoader.fetch`
  passes `tmnChange` to `build`.
- `MarketBoxCore.swift` — `MarketBuilder.build` gains `tmnChange: Double?`;
  in the `.fiat` case, only symbol `"USD"` with `display == .irt || .irr`
  (only then is the row priced by the anchor) gets `dayChangePct = tmnChange`.
  Doc comments updated (`MarketRow.dayChangePct` no longer "crypto only";
  `WallexRate.change24h` no longer "unused in v1").
- `MarketBoxWidget.swift` — the change-label gate becomes **data-driven**
  (decision 2026-09-12, user): render whenever `row.dayChangePct != nil`,
  keeping the "–" fallback. The kind check is removed; the snapshot is the
  authority and the face cannot drift from the builder. `showDayChange` still
  gates everything.
- No schema change, no settings change, no new widget (so no gallery
  descriptor bump required — the change renders on the next timeline refresh
  after install; the release itself still bumps to v1.43 per convention).

## 5. Non-goals

- No change on the CAD/EUR/AED USD row (its price is a cross rate, not the
  anchor; fiat day changes need a history source that does not exist).
- No IRR/IRT distinction in behavior — same anchor, constant ×10 scale, same
  percent.
- No fiat/gold day changes generally; no sparklines; no `7d_ch`.
- No new toggle; no new fetch; no new provider.

## 6. Open questions

None — resolved in interview (face gate) and by the data (row scoping).

## Verification

- `MarketBuilderTests`: `testBuildsAllKindsInIrt` updated to pass
  `tmnChange: 2.02` and assert the USD row carries it (its "fiat rows are
  price-only" comment is now false for the IRT USD row); new cases —
  USD-in-IRT carries the change, USD-in-IRR carries the same percent,
  USD-in-USD display is nil, CAD-in-IRT is nil, missing `tmnChange` is nil.
- `xcodebuild test -scheme DeckSharedTests` green.
- Build + install; the change renders on MarketBox's next timeline refresh
  (existing widget — no gallery re-add needed); check medium/large in an IRT
  display against the live snapshot.
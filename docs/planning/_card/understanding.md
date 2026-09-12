# Understanding: MarketBox — the Toman rate's own 24h change

## What the work is really asking

The free-market Toman anchor is the whole point of the IRR/IRT display mode:
every row in those displays is priced through the Wallex `USDTTMN` order book.
When the user also has a **USD fiat row configured** (it is a default ticker),
that row's price *is* the anchor — 1 USD priced in Toman
(`MarketConverter.fiatPrice("USD", …)` → `perUSD(1, tmn:)`, IRT = ×tmn,
IRR = ×tmn×10).

Wallex reports the anchor's own 24-hour change (`24h_ch`), and `WallexParser`
already parses it (`WallexRate.change24h`, MarketBoxSnapshot.swift:139-141, with
a fixture and a parser test) — but the loader **throws it away**:
`fetchToman()` returns only the `Double` rate (MarketBoxSnapshot.swift:375-382),
and `MarketBuilder` gives every fiat row `dayChangePct: nil`
(MarketBoxCore.swift:479). So the row an IRT/IRR user watches most renders "–"
while crypto and stock rows render "+2.0%". The ROADMAP follow-up names exactly
this: *"the Toman rate's own 24h change on the USD row (Wallex `24h_ch`,
already parsed)"* (ROADMAP.md, MarketBox entry, open follow-ups).

## What changes

The change is carried from the parser to the row that describes it. No schema
change, no new setting, no new fetch, no new provider.

1. **`MarketBoxSnapshot.swift`** — `fetchToman()` returns `WallexRate` instead
   of `Double` (rate is still required — `invalidPayload` when absent; the
   change stays optional, it is a nice-to-have per the existing comment).
   `HostMarketLoader.fetch` passes the change through to `build` as a new
   `tmnChange: Double?` parameter.
2. **`MarketBoxCore.swift`** — `MarketBuilder.build` gains `tmnChange: Double?`.
   In the `.fiat` case, only for symbol `"USD"` and only when `display == .irt
   || display == .irr` (only then is the row priced by the anchor): attach
   `dayChangePct = tmnChange`. Every other fiat row, and USD in any other
   display, stays price-only. Update the stale `MarketRow.dayChangePct` doc
   ("crypto only" — stocks already carry it) and the `WallexRate.change24h`
   comment ("unused in v1" is now false).
3. **`MarketBoxWidget.swift`** — the change label's kind gate
   (`row.kind == .crypto || row.kind == .stock`, line 221) must let the USD
   fiat row render its change. Cleanest: gate on `row.dayChangePct != nil`
   (data-driven — the snapshot decides what a row carries, the face cannot
   drift from the builder) with the existing "–" fallback. The
   `showDayChange` toggle already gates all of this.
4. **Tests** — `MarketBuilderTests`: update `testBuildsAllKindsInIrt`
   ("fiat rows are price-only" becomes "the USD row in IRT carries the anchor's
   change"); new cases: USD-in-IRT carries `tmnChange`, USD-in-IRR carries it
   (same percent — ×10 is a constant), USD-in-USD display stays nil, CAD-in-IRT
   stays nil (its price is a cross, not the anchor), missing `tmnChange` → nil.
   `WallexParserTests` already covers the parse.
5. **Docs** — ROADMAP.md M8 entry ticked on ship.

## Ambiguities / open questions for the interview

- **Which rows may carry the anchor's change?** Only the fiat USD row in
  IRT/IRR displays, because only then is the row's price the anchor. A CAD row
  in IRT is USD→CAD→Toman — its day change is not the anchor's. A USD row in
  CAD display would need open.er-api's own 24h change, which is not fetched
  (fiat stays price-only). IRT and IRR both qualify (same anchor, constant
  scale → same percent).
- **Face gate: data-driven vs kind allowlist.** Data-driven
  (`dayChangePct != nil`) cannot drift from the builder; the kind check exists
  only because fiat/gold never had changes. Gold stays nil forever, so the
  data-driven gate is strictly correct.
- **Placeholder.** The gallery placeholder draws a USD row at 201,352 Toman
  with `dayChangePct: nil` — give it a sample change so the preview shows the
  feature.
- **Backward compatibility.** `MarketRow.dayChangePct` is already in the
  schema: old snapshots decode in the new app (nil → "–"), and a new snapshot
  with a change decodes in an old app (its face ignores it — kind gate).
  Snapshot round-trip tests already exist and must stay green.

## Affected files

`native/Shared/MarketBoxSnapshot.swift`, `native/Shared/MarketBoxCore.swift`,
`native/DeckWidgets/MarketBoxWidget.swift`, `native/SharedTests/MarketBoxCoreTests.swift`,
`ROADMAP.md` (M8 tick), possibly `README.md`.

## Shell invariants checked (CLAUDE.md)

- No Swift Charts in the face. ✓ (unchanged)
- No new fetch, no new provider — the 60s tick and the keyless rule are
  untouched; a missing `24h_ch` degrades to "–", never a failed tick. ✓
- Snapshot stores converted prices; the change rides the same row. ✓
- Tolerant decode: no schema change at all. ✓
- Widget face reads nothing new from settings (`showDayChange` is existing).
  ✓
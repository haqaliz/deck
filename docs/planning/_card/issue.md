# Card: MarketBox — the Toman rate's own 24h change

**Source:** inline brief (deck-next handoff, 2026-09-12), no GitHub issue.

## Brief

MarketBox displays prices in one global display currency (USD/IRR/IRT/CAD/
EUR/AED). When the display currency is IRR or IRT, every price is converted
through the free-market Toman anchor fetched from Wallex (`USDTTMN` order
book). The anchor's **own 24-hour change** is already parsed out of the Wallex
response (`WallexRate.change24h`, from `24h_ch`) but nothing renders it — the
row that shows the Toman rate carries no day change while every crypto row and
the new stock rows do.

Recorded as the open follow-up in the MarketBox ROADMAP entry
(`ROADMAP.md`, M5): *"the Toman rate's own 24h change on the USD row
(Wallex `24h_ch`, already parsed)"* — and it is the top item of M8
(Follow-on improvements) in the same file.

Scope is deliberately small: zero new fetches, zero new providers. The data is
already in the snapshot's fetch path; this is a face/policy slice.

## Constraints inherited from the shell

- Keyless providers only — unchanged; no new requests at all.
- The agent fetches every 60s; the widget renders snapshots; the snapshot
  stores the display currency it converted for (the header never mislabels a
  mid-tick settings change).
- No Swift Charts in the widget face.
- Fiat/gold rows stay price-only (`dayChangePct: nil`) — only the Toman
  anchor's own change is in scope here.
- Partial failure follows the MarketBox one-key/several-providers pattern:
  a missing Wallex tick means no change shown, never a failed tick.
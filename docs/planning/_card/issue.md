# Card — MarketBox live coin lookup

**Type:** feat · **Slug:** `marketbox-coin-lookup` · **Branch:** `feat/marketbox-coin-lookup/aliz`
**Source:** inline brief (`deck-next`, 2026-09-05). No GitHub issue.
**Closes:** `ROADMAP.md:253-254` (MarketBox open follow-up — *"a live `/coins/list`
lookup instead of the curated symbol map"*).

## Brief

MarketBox's ticker pickers are fed by `MarketSymbolResolver.cryptoIDs`
(`native/Shared/MarketBoxCore.swift:16`) — a hand-maintained map of 43 coins that
is both the picker's source and the pricing route
(`coins/markets?ids=…`, `native/Shared/MarketBoxSnapshot.swift:265`). Anything
outside those 43 is unpickable and unpriceable, and the map silently drifts as
CoinGecko ids change. Replace it with a live, searchable lookup behind the same
twelve slot pickers, keeping tickers **picked** rather than blind-typed
(`ROADMAP.md:240` records why free text was removed).

## Caveats to probe live before the PRD

- `/coins/list` is the endpoint the ROADMAP names but is probably wrong:
  multi-megabyte, unranked, and dozens of coins share a ticker like `BTC`, which
  recreates the "unknowable symbol" problem the curated list exists to prevent.
  Compare against `coins/markets?order=market_cap_desc&per_page=250`, which
  carries symbol, name, id **and** market-cap rank in one keyless call — and is
  the endpoint MarketBox already talks to.
- CoinGecko's free tier is rate-limited. The fetch belongs to the **host app on
  picker open**, cached in an app-side sidecar (the `opencode-cursor.json`
  precedent) — not the 60s agent tick, and **not** the widget extension, which
  has no such access.
- Decide what happens to a ticker already stored whose id the live list no
  longer resolves.

## Shell invariants this must not break

- Settings live in the Deck app window only; the widget extension reads
  `settings.json` and has no keychain or network-credential access.
- Anything the extension reads must stay answerable from `settings.json`
  (CLAUDE.md: "Two settings fields are read *inside the widget extension*").
- No Swift Charts in a widget face (CLAUDE.md) — not expected to apply here.

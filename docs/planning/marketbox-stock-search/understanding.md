# Understanding — marketbox-stock-search

## What the work is really asking

MarketBox's Add Ticker sheet (`AddTickerSheet`, `DeckApp/DeckApp.swift:2585`)
searches coins live via `HostCoinSearchLoader` but lists stocks from a fixed
curated catalog (`MarketSymbolResolver.stockCatalog`, 21 entries) with a
comment warning that a live Yahoo search would share the loader's burst quota.
This work replaces the fixed catalog with **live Yahoo symbol search** —
picked, never typed — while the catalog stays as the offline/empty-query
state, exactly as `popular` does for crypto.

## What the probe settled

`docs/planning/marketbox-stock-search/probe.md` (2026-09-15):

1. `GET query1.finance.yahoo.com/v1/finance/search` is keyless, ~2.5 KB with
   `newsCount=0`, unknown queries → 200 with `count: 0`, indices searchable,
   empty `q=` → 400 (never sent: policy min length 2).
2. **Rate limiting is UA-scoped, not IP-scoped.** A browser UA 429'd within
   three requests and stayed banned 8+ minutes host-wide (chart API included);
   an app-like UA ("Deck/1.0") survived 15 requests in ~8s with no 429 at all.
   The loader already uses URLSession's default UA in production, which is why
   stock rows price every tick. **Rule: never set a browser UA.**
3. Result rows mix types and exchanges (`q=apple` top 8: 2 futures, a REIT, a
   Toronto CDR, a Thai listing). The picker must show `typeDisp`/`exchDisp`
   per row (the way crypto shows `#rank`), or a pick is blind.

## Affected files (mapped)

- `native/Shared/CoinSearch.swift` — `CoinSearchPolicy` (debounce 0.6s / floor
  2s / min length 2 / cache key) and `HostCoinSearchLoader` are the shape to
  copy; the stock search is a parallel `StockSearchHit`/parser/loader, or a
  generalized search. `HostCoinSearchLoader` is host-app-only, grep-verified.
- `native/DeckApp/DeckApp.swift:2585-2745` — `AddTickerSheet` gains a stock
  search mode in the same `.task(id: query)` pipeline; the `stocks` curated
  list stays as the empty-query state.
- `native/Shared/MarketBoxCore.swift` — `StockCatalogEntry` (display vs
  yahoo symbol split), `MarketTicker` (`symbol`/`stockSymbol`/`name`/`rank`),
  `MarketSymbolResolver.stockCatalog` (kept for the empty state), and
  `MarketFetchPlan.stockSymbols` (unchanged — the loader fetches whatever
  `stockSymbol` a picked row carries).
- `native/Shared/MarketBoxSnapshot.swift` — `HostMarketLoader` unchanged; a
  picked stock row still fetches through the existing serial 0.75s-spaced
  chart path. **No fetch-path changes.**
- `native/SharedTests/` — `CoinSearchTests.swift` is the test template.

## Open questions for the interview

1. **What kinds are searchable?** EQUITY + INDEX only, or also ETF? (ETF is
   common — VTI/SPY — but the catalog is stocks+indices today.)
2. **Filter or label the noise?** Filter FUTURE rows out, or show `typeDisp`
   and let the user choose? (`q=apple` top 8 has 2 futures.)
3. **What does the row show?** `exchDisp` ("NASDAQ") beside the symbol, like
   the crypto rank column? What about the ticker-search textfield placeholder
   ("Search coins" → "Search coins & stocks")?
4. **Display symbol vs Yahoo symbol.** A picked row stores the Yahoo symbol
   as both `symbol` and `stockSymbol`, or normalise display (`BRK-B` vs
   `BRK.B`)? The catalog splits them; search results carry one symbol only.
5. **Same policy constants?** Keep CoinSearchPolicy's 0.6/2.0/2, or restate
   for stocks? The probe found no 429 with the app UA; the browser-UA worst
   case (host-wide ban) justifies keeping the shape regardless.
6. **The "offline empty state" stays the 21-entry catalog** — confirm it
   stays exactly as is.

## Invariants touched (flag before planning)

- **Host-app-only search** — the loader must never run from `DeckAgent` or the
  extension (same rule as `HostCoinSearchLoader`, grep-verified in phase 5).
- **No face changes, no Charts** — settings/picker surface only.
- **No new `settings.json` fields read by the extension** — `MarketTicker`
  fields are already tolerant-decoded; search hits produce the same fields.
- **Keyless-only** — satisfied (no key on the search endpoint).
- A 429 must degrade the sheet, never the tick — same `Status` enum shape.
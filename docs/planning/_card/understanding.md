# Understanding: MarketBox stocks/indices

## What the work is really asking

Extend MarketBox so the user can add stocks and indices to the same priced list
as crypto/fiat/gold, in the same display currency. Not a new widget — a fourth
kind inside the existing one. The face, the partial-failure policy, the snapshot
and the currency conversion are unchanged; what changes is (a) a fourth kind
with its own provider, (b) a way to pick stock/index instruments, and (c) the
day-change row on the face that today is crypto-only.

## The live probe (run 2026-09-09, before this note)

The brief demanded the provider be settled by a live probe before any PRD.
Result: **Yahoo Finance's unofficial chart API is the working keyless source**;
Stooq is a dead end.

- **Yahoo `query1.finance.yahoo.com/v8/finance/chart/{symbol}?interval=1d&range=1d`**
  — keyless, one request, rich payload:
  - AAPL: `meta.regularMarketPrice: 316.22`, `regularMarketChangePercent: -1.172`,
    `longName: "Apple Inc."`, `currency: "USD"`, `exchangeName: "NMS"`.
  - `^GSPC` (S&P 500): same shape, `instrumentType: "INDEX"`,
    `shortName: "S&P 500"`, `regularMarketPrice: 7673.52`,
    `regularMarketChangePercent: -0.584`. Indices are the same payload.
  - Unknown symbol (`ZZZZNOTREAL99`): HTTP 200 with
    `chart.result: null`, `chart.error.code: "Not Found"` — a clean, distinct
    "no data" signal (maps to MarketBox's existing `noData` wording, not
    "source unavailable").
  - **Rate limit is the caveat, and it is exactly the documented one.** Bursts
    answered `Edge: Too Many Requests`; the same request succeeded after a ~20s
    cooldown. Controls (open.er-api, gold-api) were fine throughout, so it is
    Yahoo-specific, not the network. One request per 60s tick is comfortably
    under the burst threshold; the *picker* must not search per keystroke.
- **Stooq** (`q/l` CSV, `q/d/l`) — "page does not exist" / a JS browser-verification
  challenge, the same class of block priceto.day had (error 1015). Do not re-litigate.
- No other keyless equity source was probed because none is worth it: Twelve Data,
  Alpha Vantage, Finnhub, Marketstack, financialmodelingprep all demand an API key,
  which the shell forbids ("keyless providers only" is a MarketBox invariant).

## What changes in the shell

All touchpoints mapped. `MarketKind` gains a fourth case; everything below is
exhaustive over it today.

1. **`MarketKind`** (`MarketBoxSnapshot.swift:24`) — add `.stock`.
2. **`MarketTicker`** (`MarketBoxCore.swift:139`) — identity. `coinID` is the
   CoinGecko id and `kind` *derives* from it (`coinID` non-empty → `.crypto`).
   Stocks cannot overload it or they'd price as crypto. Minimal migration-safe
   shape: a new optional `stockSymbol` field; `kind` derives `.stock` from
   `stockSymbol` non-empty (checked after `coinID`, so the two can never collide
   in practice and the derived-kind invariant survives). Tolerant decode keeps
   old files valid.
3. **`MarketSymbolResolver`** (`MarketBoxCore.swift:103,112`) — `kind(for:)` and
   `name(for:)` need the stock branch; plus a curated **stock catalog** (symbol →
   name) for the picker, so nothing needs live search (rate limit).
4. **`HostMarketLoader.fetch`** (`MarketBoxSnapshot.swift:193`) — a `needsStocks`
   gate and a `fetchStocks` call. Serial like the other four (5×10s worst case
   is borderline against the 60s tick; CLAUDE.md's fan-out lesson is a real
   consideration — interview decision).
5. **`MarketBuilder.build`** (`MarketBoxCore.swift:346`) — `.stock` case: price =
   `regularMarketPrice`, converted via `MarketConverter.perUSD` (USD-nominated
   catalog only, v1), `dayChangePct` = `regularMarketChangePercent`. And
   `collapse` needs the stock source named ("Stocks unavailable").
6. **`YahooChartParser`** (new) — pure, unit-tested against the captured
   payloads; three states like CoinGecko (row / noData on `error.Not Found` /
   nil on parse failure).
7. **Face** (`MarketBoxWidget.swift:219`) — `changeLabel` gates on
   `.crypto`; extend to `.stock` so a stock row shows its day change on
   medium/large.
8. **Picker** (`DeckApp.swift:2585` AddTickerSheet) — a "Stocks & Indices"
   section from the curated catalog, zero network (fiatAndGold precedent at
   `:2642`). No Yahoo search in v1 (rate limit + the CoinGecko picker already
   proves the pattern for a future live search).
9. **Tests** — `MarketBoxCoreTests`, `MarketBoxParsersTests`, `MarketTickerTests`
   get the new case; snapshot decode of old files must still pass (no `.stock`
   rows in old snapshots).

## Ambiguities / open questions for the interview

- **Curated catalog vs live search.** Curated-only in v1 (matches "picked, never
  typed" + avoids Yahoo's rate limit). What's in it: major US stocks + the main
  US indices (^GSPC, ^IXIC, ^DJI, ^RUT?). Non-US instruments are USD-nominated
  only, so conversion stays one path.
- **Day change scope.** Yahoo gives it free. Show it on stock rows (medium/large,
  same as crypto) or keep stocks price-only in v1?
- **Serial vs concurrent fetch.** Keep the 4-source serial loader + a 5th, or
  fan out (first `withThrowingTaskGroup` in MarketBox)? The tick lesson in
  CLAUDE.md says fan-out is the safe default past a handful of sources.
- **Symbol display.** `^GSPC` reads oddly on a 36pt-wide row; the catalog could
  carry a display symbol ("SPX") while the fetch uses `^GSPC`. Separate
  `symbol` (display) and `stockSymbol` (fetch) — worth confirming.
- **The 12-row cap and tickerCount** already cover stocks (they're just more
  rows in the same list).

## Affected files

`native/Shared/MarketBoxCore.swift`, `MarketBoxSnapshot.swift`, `CoinSearch.swift`
(no — catalog lives in Core), `native/DeckWidgets/MarketBoxWidget.swift`,
`native/DeckApp/DeckApp.swift`, `native/DeckAgent/main.swift` (no change — it
calls `HostMarketLoader.fetch`), `native/SharedTests/*`, `README.md`,
`ROADMAP.md`, `scripts/demo-data.sh` (sanitize a stock row), version bump in
`project.yml` (CFBundleShortVersionString/CFBundleVersion).

## Shell invariants checked (CLAUDE.md)

- No Swift Charts in the face — unchanged (stocks are rows, no chart). ✓
- One widget, agent-pumped, 60s, settings in app only, snapshot renders. ✓
- Keyless providers only — Yahoo is keyless; picker never on the agent path. ✓
- Tickers picked, never typed — curated stock catalog. ✓
- No `serverURL`/`.enabled` reads inside the extension. ✓
- Tolerant decode everywhere a new field lands. ✓
- Version bump required for the extension to pick up the new kind. ✓
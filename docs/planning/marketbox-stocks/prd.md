# MarketBox: stocks & indices

Slug: `marketbox-stocks`. A fourth kind inside MarketBox — not a new widget.

## 1. Ask

Extend MarketBox so stocks and indices can be added to the same priced list as
crypto/fiat/gold, in the same display currency. Instruments come from a curated
US catalog (picked, never typed), and stock rows carry a day change on
medium/large like crypto rows do.

## 2. User-visible spec

### Front face

- Stock/index rows join the existing list in display order, under the same
  `tickerCount` cap. Nothing new is drawn — a stock row is symbol, price, day
  change, exactly like a crypto row.
- Display symbol is friendly, not the raw Yahoo symbol: `SPX` not `^GSPC`,
  `AAPL`, `NVDA`, `IXIC`, `DJI`.
- Day change on medium and large (up/down colors, same rule as crypto); the
  small face stays price-only. A stock with no change renders `–`.
- Note line, same policy as today: all stock calls fail → `Stocks unavailable`;
  a symbol Yahoo answers "Not Found" about → `No data: X`.

### Settings (back face)

- **Add Ticker…** sheet gains a **Stocks & Indices** section beside Popular and
  Fiat & Gold. Offline, zero network, same row shape (symbol + name + rank n/a).
- No new controls: `tickerCount`, `showDayChange`, colors and display currency
  already cover stock rows. The helper caption under the Tickers list is
  updated to mention stocks.

## 3. Data source

**Yahoo Finance unofficial chart API** — probed live 2026-09-09, see `probe.md`.

- Per-symbol `GET https://query1.finance.yahoo.com/v8/finance/chart/{symbol}?interval=1d&range=1d`,
  keyless, one small JSON payload.
- Fields used: `meta.regularMarketPrice` (USD), `meta.regularMarketChangePercent`
  (day change vs previous close), `meta.shortName`/`longName` (cached name),
  `chart.error.code == "Not Found"` (unknown/delisted symbol → the `noData`
  signal).
- **Burst rate limit is the defining constraint.** Measured: ~6 requests in
  ~10s answer `Edge: Too Many Requests`; the same request succeeds after a
  ~20s cooldown. The batched `v7/finance/quote` endpoint (one call for many
  symbols) now answers `Unauthorized`. So the loader fetches **serially, one
  v8 call per stock ticker, with inter-request spacing (~0.75s)**. 8 stock
  rows ≈ 8 calls ≈ 6–9s per tick — inside the 60s cadence, outside the burst
  window. This is a loader-internal constraint, not a shell change.
- **Cadence:** agent 60s, unchanged. One fresh spaced burst per tick.
- **429 abort:** if a stock call answers 429 (or any transport failure, since a
  rate-limited first call means the rest are doomed too), the stock pass stops
  early and that tick contributes no stock rows — the note carries
  `Stocks unavailable`, the next tick retries. Never spend the whole tick on a
  doomed pass.
- **Unavailable:** per-symbol failures omit that row; all fail → note
  `Stocks unavailable`; no stock outcome ever throws the whole fetch, so the
  last-good snapshot stands. Partial results render with a note (the existing
  MarketBox policy).

## 4. Shell fit

Reuses the MarketBox agent-pumped path end-to-end. The exhaustive `MarketKind`
gains a case; every consumer below is touched deliberately:

1. `MarketKind` — add `.stock` (`MarketBoxSnapshot.swift`).
2. `MarketTicker` — new optional `stockSymbol` field (the Yahoo symbol,
   `^GSPC`); `kind` derives `.stock` from it, checked after `coinID` so a stock
   can never price as crypto. Tolerant decode; old files decode with an empty
   `stockSymbol`. The display `symbol` stays the friendly one (`SPX`).
3. `MarketSymbolResolver` — the curated `stockCatalog` (display symbol, friendly
   name, Yahoo symbol). No `kind(for:)`/`name(for:)` branch needed: a stock's
   kind derives from `stockSymbol` and its name is stored at pick time; those
   two helpers only serve the legacy symbol-migration path, which never sees
   stocks.
4. `YahooChartParser` + `StockQuote` (new, pure) — parses the v8 payload into
   the three states the builder needs (priced / `Not Found`→noData / parse
   failure→nil).
5. `HostMarketLoader.fetch` — `needsStocks` gate + serial spaced `fetchStocks`
   alongside the existing four providers.
6. `MarketBuilder.build` — `.stock` case: `perUSD(regularMarketPrice)` for the
   display currency, `dayChangePct = regularMarketChangePercent`; `collapse`
   names the whole stock source once (`Stocks unavailable`).
7. `MarketBoxWidget.changeLabel` — include `.stock` in the day-change gate
   (`row.kind == .crypto` → `row.kind == .crypto || row.kind == .stock`).
8. `AddTickerSheet` — Stocks & Indices section from the catalog, offline.
9. Tests — `MarketBoxCoreTests`, `MarketBoxParsersTests`, `MarketTickerTests`
   new cases; old-snapshot decode stays green (no `.stock` in old files).
10. Docs/data — README.md, ROADMAP.md, `scripts/demo-data.sh` (sanitize a stock
    row), version bump in `project.yml` (required for the extension to pick up
    the new kind).

**Deviations from shell invariants:** none. Keyless-only preserved; no Charts in
the face; settings in the app only; the extension reads nothing new from
`settings.json` beyond a tolerant-decoded `stockSymbol`.

## 5. Non-goals

- **Live Yahoo search in the picker.** Curated catalog only in v1. Yahoo's
  search endpoint exists but adds a second rate-limited surface; the CoinGecko
  picker (`CoinSearchPolicy`) proves search as a later follow-up.
- **Non-US instruments.** The catalog is USD-nominated US stocks + US indices,
  so conversion stays the one existing path.
- **Sparklines/history.** No Charts in faces; the chart API carries history but
  nothing renders it in v1.
- **Anything beyond price + day change** — no volume, market cap, or split info.
- **A separate stocks widget.** Stays inside MarketBox.

## 6. Decisions (interview 2026-09-09)

- Curated catalog (US stocks + US indices), offline picker. ✅
- Day change shown on medium/large; small price-only (crypto rule). ✅
- US stocks + US indices in v1. ✅
- Serial spaced per-symbol fetch (the probe settled it: no batch endpoint
  works, bursts 429).

## 7. Open questions

None blocking. The 0.75s spacing constant and the curated catalog contents are
plan-phase decisions (constants in `MarketSymbolResolver` / the loader).

## 8. Self-critique

Pressure-tested against the shell invariants and the probe.

🔴 **Red: none.** Keyless-only holds; no Charts in the face; settings in the app
only; the extension reads nothing new (the widget renders snapshot rows, and a
`MarketRow` with `kind == .stock` is only gated in `changeLabel`). The
snapshot-decode risk of an old widget reading a `.stock` row is covered by the
mandatory version bump — agent, app and extension ship in one bundle, so the
new kind and the new descriptor land together.

🟡 **Amber, with fixes folded in above:**

- **`dayChangePct` carries two meanings.** The field is documented "24h percent
  change — crypto only"; stocks put a *day* change in it. The field name is
  kept (snapshot schema, already "day" in spirit); the doc comment is updated
  so the field reads honestly. Folded into the code change.
- **First-429 abort.** An uncoordinated pass would spend N×0.75s on a doomed
  set of calls. Now specified: stop the stock pass on the first failure. Folded
  into §3.
- **Weekend / pre-market readings.** Yahoo returns the last close on weekends
  and the regular-session price during pre-market, so a weekend snapshot shows a
  stable price with a ~0.0 change rather than blanking. Acceptable; the plan's
  verification includes a build that renders rows on a closed market.
- **`shortName` vs `longName`.** AAPL agrees; some tickers differ. Parser
  prefers `longName`, falls back to `shortName`. Plan item.
- **Catalog display-symbol collisions.** The list is deduped by display `symbol`
  and a collision with a coin is refused out loud (the existing
  `MarketTickerList.adding` behavior) — but the catalog itself must not
  self-collide (no two entries share a display symbol). A plan check.
- **Serial shape vs the fan-out lesson.** The stock pass is deliberately serial
  and spaced because the source rate-limits bursts; the other four providers
  stay as they are. Do **not** `withThrowingTaskGroup` the Yahoo calls — that
  would re-create the burst. Stated so a later reader doesn't "fix" it.
- **Version bump is load-bearing.** Forgetting it leaves the old descriptor set
  in the gallery while the new snapshot contains `.stock` rows — a blank
  MarketBox that decodes nothing. The plan's first verification step is the
  bump.
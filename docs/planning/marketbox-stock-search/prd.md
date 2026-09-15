# MarketBox: live stock search

Slug: `marketbox-stock-search`. A follow-on slice inside MarketBox's settings —
not a new widget, no face changes.

## 1. Ask

Replace the fixed **Stocks & Indices** catalogue in the Add Ticker sheet with a
**live symbol search**, keeping the catalogue as the offline/empty-query state
(the `Popular` precedent for crypto). Search covers equities, US indices and
ETFs via Yahoo's keyless search endpoint; hits are picked, never typed, and
store the Yahoo symbol the loader already fetches. Fiat and gold stay curated —
they are not Yahoo rows at all.

## 2. User-visible spec

### Settings (back face) — the only changed surface

- The Add Ticker sheet's one search field now searches **coins and stocks at
  once**. A query of ≥ 2 chars runs both searches (CoinGecko + Yahoo) and
  renders the hits grouped: `Coins` and `Stocks & ETFs` sections, each with
  the existing row shape (symbol, name, leading slot).
- **Leading slot:** coin hits keep `#rank` (fresh from CoinGecko); stock hits
  show the **exchange** (`NASDAQ`, `NYSE`, …) — the interview decision — with
  the type label (`Equity`/`ETF`/`Index`) as secondary text, so `AAPL` and
  `AAPL.TO` stay distinguishable and a future row can't read as a stock.
- **Noise is filtered, not shown:** FUTURE (and any non
  EQUITY/INDEX/ETF) rows are dropped before rendering — `q=apple` keeps AAPL,
  AAPX (ETF) and drops `SAAPL=F`/`XAAPL=F`; a REIT that Yahoo returns for the
  query is kept (it *is* an equity, and the exchange label makes it honest).
- Empty query → the curated sections exactly as today (Popular, Fiat & Gold,
  **Stocks & Indices** — the offline catalogue, zero network). This is the
  brief's "offline empty state"; the catalogue is not deleted.
- TextField placeholder becomes `Search coins & stocks`.
- No results → `No coins or stocks match that.`; Yahoo 429 → the existing
  `Search is busy — try again in a moment.`; offline/failed wording unchanged.
- A picked stock row stores the Yahoo symbol as returned (`AAPL`, `^GSPC`,
  `BRK-B`) in both `symbol` and `stockSymbol` — one source of truth, no
  normalisation table. The catalogue's friendly names (`SPX` vs `^GSPC`)
  apply only to catalogue picks.
- Adding still refuses duplicates out loud (existing `MarketTickerList.adding`
  path, unchanged).

### Front face

- **No changes at all.** A picked row flows through the existing serial,
  0.75s-spaced chart loader exactly like a catalogue pick. Nothing new is
  drawn, nothing new is read from `settings.json` by the extension.

## 3. Data source

**Yahoo Finance unofficial search** — probed live 2026-09-15, see `probe.md`.

- `GET https://query1.finance.yahoo.com/v1/finance/search?q={query}&quotesCount={n}&newsCount=0&listsCount=0`
  — keyless, ~2.5 KB with `newsCount=0`, clean 200-with-`count:0` for unknown
  queries, `400` for an empty `q=` (never sent: the 2-char policy minimum).
- Fields used per hit: `symbol` (fetch + display), `longname`/`shortname`
  (cached name), `quoteType` (the EQUITY/INDEX/ETF filter), `typeDisp`,
  `exchDisp` (the row labels).
- **Rate limiting is UA-scoped, not IP-scoped — the probe's load-bearing
  finding.** A browser UA 429'd within three requests and stayed banned
  **8+ minutes host-wide, the chart API included**; an app-like UA survived
  15 requests in ~8s with no 429 at all. The loader already uses
  `URLSession`'s default UA in production (that is why stock rows price every
  tick). **Rule: the search loader must never set a browser UA.**
- **Posture stays shared-budget, even though the app UA showed headroom:**
  the worst case measured is a host-wide ban that blanks the loader's chart
  rows for minutes, so the search keeps the `CoinSearchPolicy` shape —
  debounce (0.6s), per-source floor (2s), per-query cache, host-app-only,
  and a 429 that degrades the sheet and never retries hard.
- The two searches (CoinGecko + Yahoo) run **concurrently per query**
  (`async let` — two requests, not a fan-out; measured fine) with separate
  `lastRequest` stamps so each provider keeps its own 2s floor.
- **Cadence:** user-interaction only. Never from `DeckAgent`, never from the
  widget extension, never on a timeline (the `HostCoinSearchLoader` rule,
  grep-verified in phase 5).

## 4. Shell fit

- `native/Shared/CoinSearch.swift` — the policy/loader shape to mirror:
  a `StockSearchHit`, `StockSearchParser`, `StockSearchPolicy`-free reuse of
  `CoinSearchPolicy` (same constants, per-source stamps), `HostStockSearchLoader`
  (host-app-only, URLComponents, timeout 10s, 429 → `rateLimited`).
- `native/DeckApp/DeckApp.swift` — `AddTickerSheet` (search pipeline + the
  grouped sections; `stocks` curated list stays as the empty state).
- `native/Shared/MarketBoxCore.swift` — `MarketTicker` unchanged (search hits
  fill the existing fields); `stockCatalog` unchanged (empty-state only).
- `native/Shared/MarketBoxSnapshot.swift` — **untouched**; the fetch path is
  not part of this work.
- Tests: new `StockSearchParserTests` + sheet-independent policy cases in
  `native/SharedTests/`, fixture payload captured from the probe.
- **Invariant check:** no Charts, no face change, no new extension-read
  settings, keyless-only, host-app-only search. No deviations.
- New source files require `xcodegen generate` before the suite picks them up
  (CLAUDE.md); no version bump (no new widget).

## 5. Non-goals

- **No fetch-path changes** — the serial spaced chart loader stays exactly as
  shipped; a search pick is just a ticker with a `stockSymbol`.
- **No browser UA anywhere** in the search or loader.
- **No fiat/gold search** — curated only (they are not Yahoo rows).
- **No query history, no favourites, no "recently picked".**
- **No symbols outside Yahoo's search space** (crypto stays CoinGecko).
- **No volume, market cap, sparkline, or anything beyond symbol + name +
  type/exchange** in a hit.
- **No change to the catalogue's display symbols** (`SPX` stays `SPX` for
  catalogue picks).

## 6. Decisions (interview 2026-09-15)

- Equities + indices + **ETFs** are searchable. ✅ (user)
- Noise is **filtered** (non-EQUITY/INDEX/ETF dropped) and the rest is
  **labelled** (typeDisp + exchDisp). ✅ (user)
- The leading slot shows the **exchange**, type as secondary text. ✅ (user)
- One search field, grouped results — no mode toggle.
- Display = raw Yahoo symbol; no normalisation table.

## 7. Open questions

None blocking. `quotesCount` default (probed at 3–8; pick 8) and the exact
secondary-text layout are plan-phase constants.

## 8. Self-critique

Pressure-tested against the shell invariants and the probe.

🔴 **Red: none.** No face change, no Charts, no new extension-read settings
fields, keyless-only holds, host-app-only holds (mirrors a grep-verified
precedent).

🟡 **Amber:**

- *The 429 worst case is host-wide and minutes-long* — the sheet's `busy`
  wording must not imply "retry soon"; the next keystroke (a new query) is the
  retry, never a timer. The policy shape already delivers this; the wording
  "try again in a moment" is reused as-is.
- *Duplicate symbols across sections* — the same symbol can appear in Coins
  and Stocks & ETFs (e.g. a crypto that Yahoo also prices). Two sections mean
  no collision at render time; `adding` refuses the second pick out loud.
- *Foreign equities stay visible* (`AAPL.TO`) — labelled with their exchange;
  a user can pick one, and the loader prices it fine. Accepted by the
  interview ("label the rest").
- *`^GSPC`-style display symbols on the face* — search picks display the raw
  Yahoo symbol, catalogue picks display friendly names. Accepted: one source
  of truth beats a normalisation table that can drift from what the loader
  fetches.
# MarketBox — inline brief (deck-next → dbf feat marketbox)

Last unshipped M5 widget candidate (`ROADMAP.md:196`): "configured tickers/crypto:
price, day change, sparkline. Near line-for-line clone of the WeatherBox agent
fetch block."

## User requirements (from deck-begin-fast interview)

- **Mixed asset kinds**, all priced in one global **display currency**:
  - crypto (BTC, ETH, TON, …) — CoinGecko free
  - fiat (USD, CAD, EUR, …) — open.er-api FX rates
  - gold 1 gram — gold spot price, converted to display currency
  - (stocks explicitly out of scope for now)
- **Display currency picker (global, one for all rows):** USD / IRR / IRT.
  - IRT (Toman) = IRR (Rial) ÷ 10.
  - Conversion from the USD price via a live FX rate (open.er-api: 1 USD ≈
    1.52M IRR today). Day-change % and sparkline stay currency-independent.
- Ticker entry: comma-separated **symbols** (BTC, ETH, TON) in settings —
  deck-idiomatic text list (like GitBox repo paths).
- Face layout: rows with **per-row sparkline**. Small: 2 rows · Medium: 4 ·
  Large: 8 (proposed; confirm in PRD).

## Data-source probe (2026-08-24, before the PRD)

- CoinGecko `/simple/price` and `/coins/markets` free tier: **no `irr`/`irt`**
  vs_currency (confirmed in `supported_vs_currencies` — only usd/try/etc).
  But `/coins/markets?vs_currency=usd&ids=...&price_change_percentage=24h&sparkline=true`
  returns price + 24h % + 7-day sparkline array, no key, one call for all ids.
- CryptoCompare (min-api.cryptocompare.com): now **401 API key required**
  (CoinDesk takeover) — dead end for no-key use.
- open.er-api.com `latest/USD`: free, no key, 166 currencies including **IRR
  (1,523,203 per USD)** and CAD — single source for the display conversion.
- gold-api.com `price/XAU`: free, no key — XAU spot ≈ $4,635/oz → per gram
  (÷ 31.1035). Price only, no history/change field.
- Yahoo chart API (query1.finance.yahoo.com): works for BTC-USD, ETH-USD,
  GC=F (gold futures, has history), CAD=X, USDIRR=X (≈1.37M, differs from
  open.er-api) — a possible future source for fiat/gold sparklines, but it is
  an unofficial scrape (flaky, rate-limited) and **not** used in v1.

## Design direction

- Agent (DeckAgent/main.swift) fetches: CoinGecko (all crypto in one call) +
  open.er-api (FX) + gold-api.com (if GOLD in list); resolves symbols → kinds;
  converts every price to the display currency; writes `marketbox.json` +
  `fetch-marketbox.json`. Reuses the whole `FetchStatus` / `FetchChip` /
  `FetchClassifier` machinery with a new `FetchSource.marketbox`.
- Widget: clone WeatherBoxWidget's provider shell; rows = symbol + price in
  display currency + 24h change + per-row sparkline (crypto). Fiat/gold rows
  may show price-only in v1 (no 24h%/sparkline source without Yahoo) — confirm.
- Settings: `MarketBoxSettings` (tickers list, display currency, show options,
  colors) in Shared/DeckSettings.swift + tab in DeckApp/DeckApp.swift. Version
  bump in native/project.yml (1.21 → 1.22 / 22) so WidgetKit picks up the new
  descriptor.

## Open questions for the PRD interview

1. Fiat/gold 24h change + sparkline: price-only in v1, or add Yahoo GC=F /
   CAD=X history now?
2. Gold symbol spelling and unit: `GOLD` = 1 gram? What about `XAU` (oz)?
3. Row counts per size and where the sparkline sits on the small face.
4. How strict to be when a symbol doesn't resolve to a known kind.
5. Display-currency list: just USD/IRR/IRT, or allow CAD/etc. as display too?

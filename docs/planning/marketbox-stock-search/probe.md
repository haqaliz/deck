# Probe: keyless Yahoo search for the stock picker (2026-09-15)

Decided whether and how MarketBox's Add Ticker sheet can search stocks live.
Run from the dev machine before the PRD.

## The endpoint

`GET https://query1.finance.yahoo.com/v1/finance/search?q={query}&quotesCount={n}&newsCount=0&listsCount=0`

- **Keyless.** Works with no token, no cookies.
- Returns `{count, quotes:[{symbol, shortname, longname, quoteType, typeDisp,
  exchDisp, exchange, score, isYahooFinance, …}], news:[], …}`. With
  `newsCount=0` the payload is small (~2.5 KB for 7 quotes) — the news list is
  otherwise bundled in.
- `quotesCount` caps the result rows (probed with 3–8).
- **Unknown query** (`q=zzzznotrealco`) → HTTP 200, `count: 0`, empty `quotes`
  — a clean no-results signal, no error shape to special-case.
- **Empty `q=`** → HTTP **400** — but the picker never sends it: the
  CoinSearchPolicy minimum length (2) already guards that.
- **Indices are searchable**: `q=^GSPC` and `q=sp500` both return the S&P 500
  (`quoteType: INDEX`, `symbol: "^GSPC"`).

## The rate limit — UA is the whole difference

- **Browser-like UA → long, IP-wide ban.** With a `Mozilla/5.0…` UA, three
  requests within seconds 429'd (`Edge: Too Many Requests`) and stayed 429'd
  for **8+ minutes** — on `query1` *and* `query2`, and the **chart API on the
  same host 429'd too** (the ban is host-wide, not endpoint-specific). The
  09-09 chart probe's "~20s recovery" does not hold for this UA; the ban is
  longer and escalating. Recovered instantly by switching UA, so it is
  **UA-scoped, not IP-scoped**.
- **App-like UA → no limit found.** With `User-Agent: Deck/1.0 (macOS)`:
  15 requests in ~8s all 200, another after 5s all 200. The 429 ceiling was
  **not found** — this is what the loader already sends in production
  (`URLSession` default), which is why stock rows price every tick.
- Implication for the picker: `URLSession.shared`'s default UA is the safe
  one — **never set a browser UA**. The CoinSearchPolicy shape (debounce,
  floor, per-query cache) is still kept because the worst case (a ban that
  blanks the loader's chart rows for minutes) is host-wide; the sheet must
  degrade, never retry hard, and nothing on a keystroke.

## Noise in the results

`q=apple` top 8: AAPL (Equity, NASDAQ), SAAPL=F and XAAPL=F (**FUTURE** rows),
APLE (Apple Hospitality REIT — a different company), AAPL.TO (Toronto CDR),
AAPX (ETF), AAPL19.BK (Thailand). So the quotes list mixes types, exchanges
and unrelated companies; the picker must show `typeDisp`/`exchDisp` beside
each row (the way the coin search shows rank) so a pick is never blind.

## Conclusion

Yahoo search is the picker's source, keyless, with a clean no-results signal.
Same host as the chart loader, so the search keeps the shared-budget posture:
host-app-only, policy-shaped, degrade-the-sheet. Payload fields to carry into
`MarketTicker`: `symbol` (fetch + display), `longname`/`shortname`, and the
`quoteType` + `exchDisp` disambiguators.
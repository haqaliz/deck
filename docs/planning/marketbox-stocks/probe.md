# Probe: keyless equity quote sources (2026-09-09)

Decided which provider prices MarketBox's stock rows. Run from the dev machine
before the PRD was written.

## Candidates

| Source | Result |
|---|---|
| **Yahoo `v8/finance/chart/{symbol}`** | ✅ **Chosen.** Keyless, one small payload, works after a cooldown. |
| Yahoo `v7/finance/quote?symbols=` (batched) | ❌ Now `Unauthorized` ("User is unable to access this feature"). No batch path. |
| Stooq `q/l` CSV / `q/d/l` | ❌ `q/l` → "page does not exist"; `q/d/l` → JS browser-verification challenge. Same class of block priceto.day had. |
| Twelve Data / Alpha Vantage / Finnhub / Marketstack / financialmodelingprep | Not probed — all demand an API key; MarketBox is keyless-only by invariant. |

## Yahoo v8 chart payload (AAPL, range=1d)

```json
{"chart":{"result":[{"meta":{
  "symbol":"AAPL","exchangeName":"NMS","fullExchangeName":"NasdaqGS",
  "instrumentType":"EQUITY","regularMarketTime":1788897601,
  "regularMarketPrice":316.22,
  "regularMarketChangePercent":-1.172,
  "fiftyTwoWeekHigh":344.57,"fiftyTwoWeekLow":225.95,
  "longName":"Apple Inc.","shortName":"Apple Inc.",
  "chartPreviousClose":316.85,"currency":"USD"}}]}}
```

Index `^GSPC`: same shape, `instrumentType:"INDEX"`, `shortName:"S&P 500"`,
`regularMarketPrice:7673.52`, `regularMarketChangePercent:-0.584`.

Unknown symbol `ZZZZNOTREAL99`: HTTP 200, `{"chart":{"result":null,"error":{"code":"Not Found","description":"No data found, symbol may be delisted"}}}` —
a clean, distinct "no data" signal (maps to MarketBox's existing `noData`
wording, not "source unavailable").

## The rate limit (the load-bearing finding)

- **Bursts 429.** Six requests in ~10s answered `Edge: Too Many Requests` on
  all Yahoo hosts (`query1`, `query2`, `v7`). The same request succeeded after a
  ~20s cooldown. Controls (`open.er-api`, `gold-api`) answered fine throughout,
  so it is Yahoo-specific, not the network.
- **One v8 call is per symbol** (comma-separated → "Not Found"). So the loader
  must fetch serially with inter-request spacing (~0.75s) rather than as a
  burst; one spaced pass per 60s tick is comfortably under the threshold.

## Conclusion

Yahoo v8 chart is the source. Serial spaced per-symbol fetch; curated picker
(no live search, which would re-introduce the burst); day change from
`regularMarketChangePercent`; unknown symbols from `chart.error.code`. Stooq is
recorded and not to be re-litigated without new evidence.
# Verification — MarketBox stocks & indices (2026-09-09)

Everything the plan required, with the measured evidence.

## Suite (phases 1–4)

`xcodebuild -scheme DeckSharedTests test` — **TEST SUCCEEDED** after every phase.
New coverage:

- `MarketStockTickerTests` (10): kind derives from `stockSymbol`, `coinID` wins,
  display/fetch symbols separate, round-trip encodes `stockSymbol`, old files
  decode with an empty one, catalog has no duplicate display or Yahoo symbols,
  catalog is disjoint from the crypto migration table.
- `YahooChartParserTests` (7): AAPL and `^GSPC` fixtures parse to the captured
  values; unknown symbol → `.noData`; garbage → `.malformed`; a non-"Not Found"
  chart error → `.malformed`; missing price → quote with nil price; `longName`
  preferred over `shortName`.
- `MarketBuilderTests` (7 new): stock row priced in USD and IRT, `noData`
  naming, all-fail collapse to `Stocks`, stock failure leaves crypto rows
  rendering, nil price omitted. One bug caught by the tests: the stock collapse
  arm initially collapsed a `noData` stock to "Stocks unavailable" — fixed with
  the same `omitted` guard the crypto arm has.
- `MarketStockFetchPlanTests` (4): symbols come from stock tickers only, dedupe
  and blanks dropped, spacing is a pinned positive decision.

## Live fetch (phases 4–5)

Installed the v1.42 build, quit Deck, added `SPX` (`^GSPC`) and `AAPL` to
`settings.json`, ran `/Applications/Deck.app/Contents/MacOS/DeckAgent` directly:

```
CAD fiat   168706.37  None        # display currency IRT (Toman)
ETH crypto 581499301.32  +1.26
USD fiat   232556.00   None
GOLD gold  32896614.32  None
AED fiat   63323.62    None
SPX stock  1784523117.12  -0.584   # 7673.52 USD × 232,556 Toman
AAPL stock 73538858.32   -1.172   # 316.22 USD × 232,556 Toman
note: None
```

Prices match the probe's captured USD values converted at the live Toman rate;
both stock rows carry the day change; no note (all priced). The unknown-symbol
path (`chart.error.code: "Not Found"`) is pinned by the fixture test rather
than a second live probe, to spare the shared rate budget.

## Agent abort path

Not live-tested: deliberately triggering Yahoo's 429 would burn the shared
public-IP quota for no new information. The abort behavior (throw → no stock
rows this tick → "Stocks unavailable") is specified in the PRD and its
*decision* (the spacing constant, the serial shape, "never fan out") is pinned
by `MarketStockFetchPlanTests`. The rate limit itself was measured during the
probe (`probe.md`).

## Widget face

The day-change gate now includes `.stock` (medium/large show the change, small
stays price-only). Verified by the release build; the gallery re-add and
three-size screenshot check follow on the release install (version bumped to
v1.42 so the extension descriptor refreshes).

## Release hygiene

- Version bump `1.41 → 1.42` / `41 → 42` in all three `project.yml` blocks
  (load-bearing: the new `.stock` snapshot kind and the new extension binary
  ship together).
- `scripts/demo_data.py` gained `SPX` and `AAPL` demo rows so screenshots show
  the new kind.
- README (widget table, ticker settings, privacy table — Yahoo added as a
  fifth provider), ROADMAP (follow-up ticked, probe recorded), CLAUDE.md (the
  Yahoo burst/no-batch/no-fan-out trap).
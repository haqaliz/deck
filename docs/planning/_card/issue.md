# Card: MarketBox stocks/indices

**Source:** inline brief (deck-next handoff), no GitHub issue.

## Brief

Extend MarketBox with stocks/indices rows alongside crypto/fiat/gold, priced in
the same display currency (USD/IRR/IRT/CAD/EUR/AED, free-market Toman anchor).

- Recorded as an explicit "out of scope for now" non-goal in the MarketBox PRD
  (`docs/planning/marketbox/prd.md:144`) — a scope decision, not a blocker.
- Listed as an open follow-up in ROADMAP.md:294 ("Open follow-ups: …
  stocks/indices, …").
- **First slice is a live probe of a keyless equity quote source.** Yahoo is the
  only documented working precedent and it is a flaky unofficial scrape
  (`docs/planning/marketbox/prd.md:83`) — excluded for fiat/gold history, and
  the same caveat applies to equities. The probe must settle the provider before
  any PRD is written.
- **One shell touch to plan for:** the Add Ticker… search sheet is
  CoinGecko-catalog-specific (`/search?query=`), so stocks need their own
  search/pick catalog (or a second catalog source) behind the same "picked,
  never typed" rule.
- Follow the MarketBox one-key/four-providers partial-failure pattern: some rows
  is an answer with a note, none throws, the last good snapshot stands.
- Fiat/gold stay price-only until a free no-key history source appears
  (unchanged; only equities are in scope here).

## Constraints inherited from the shell

- Keyless providers only — MarketBox's four existing providers (CoinGecko,
  Wallex, gold-api, open.er-api) all run with no API key; an equity source that
  demands a key is out unless it beats the flaky-Yahoo tradeoff after a live
  probe.
- The agent fetches every 60s; the widget renders snapshots; the snapshot stores
  the display currency it converted for (header never mislabels a mid-tick
  setting change).
- No Swift Charts in the widget face (silently drops the widget from the
  gallery).
- Tickers picked, never typed blind.
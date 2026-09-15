# Brief — marketbox-stock-search

Add live symbol search to MarketBox's Add Ticker sheet, replacing the fixed
Stocks & Indices catalog as the primary picker while keeping it as the offline
empty state.

Reuse the `CoinSearchPolicy` shape exactly: debounce, request floor, per-query
cache, host-app-only execution, and a 429 that degrades the sheet rather than
any agent tick.

Probe Yahoo's search endpoint before writing the PRD — the chart API on the
same host bursts 429 at ~6 requests in 10s
(`docs/planning/marketbox-stocks/probe.md`), so the search must share the
loader's budget defensively and never be fanned out.

No face changes; settings only.

Source: deck-next pick (2026-09-15), from ROADMAP.md M8.

# Understanding — MarketBox live coin lookup

Phase 2 of `deck-begin-fast`. Read before the PRD.

## What the work is really asking

MarketBox can price any CoinGecko coin — the loader already calls
`coins/markets?ids=…` (`Shared/MarketBoxSnapshot.swift:265`). What it cannot do
is let the user *name* one. `MarketSymbolResolver.cryptoIDs`
(`Shared/MarketBoxCore.swift:16`) is a hand-written map of **43 symbols → ids**
that serves two masters at once:

1. the settings picker's menu (`allPickableSymbols` → `DeckApp.swift:2523`), and
2. the agent's symbol→id resolution at fetch time
   (`MarketBoxSnapshot.swift:263`, `MarketBuilder.build` → `cryptoID(for:)`).

Because settings store a **symbol** (`tickers: ["BTC", "ETH", "USD", "GOLD"]`,
`DeckSettings.swift:1091`), the agent must resolve it, so the map has to exist in
the agent too. That coupling — not the picker — is what caps MarketBox at 43
coins.

## The design hinge

**Store the CoinGecko id in settings, not just the symbol.** Then the picker is
the only thing that ever resolves, the agent's fetch becomes a pure `ids=` join
with no lookup step, and the curated map stops being load-bearing. It also
answers the "stored ticker whose id no longer resolves" question, because a
stored id is exactly what a live list can be checked against.

This keeps every shell invariant: settings still live in the app only, the widget
extension still reads nothing but the snapshot (`grep -rn "tickers\|MarketSymbolResolver"
native/DeckWidgets/` is clean — the CLAUDE.md "two fields read inside the
extension" trap does **not** apply here), and no widget-face code changes.

## Live probe (2026-09-05) — five findings, three change the design

Every number below was measured against the live keyless API, not assumed.

### 1. `/coins/list` is the wrong endpoint, exactly as suspected

**1.24 MB, 19,594 coins, `{id, symbol, name}` only — no rank, no price.**
And symbols are not unique: **2,396 of 15,090 distinct symbols map to more than
one coin.** `BTC` is 11 coins, `ETH` 14, `PEPE` 21, `GOLD` 9. Alphabetically
`batcat` precedes `bitcoin`. A symbol-keyed picker over this list recreates the
"unknowable symbol" problem the curated list was introduced to kill
(`ROADMAP.md:240`). **Rejected.**

### 2. `/search?query=` is the right one

`GET /api/v3/search?query=pepe` → **10.5 KB**, 25 coins, keyless, **already
ordered by market cap**, and each hit carries `id`, `symbol`, `name`,
`market_cap_rank` and a `thumb` icon URL. Server-side search means nothing large
is ever held locally. Rank 56 `pepe` is the first hit for "pepe"; the 21 impostors
sort below it.

### 3. `/coins/markets?order=market_cap_desc&per_page=250` is the browse list

**197 KB**, top 250 by market cap with `market_cap_rank`, `id`, `symbol`, `name`.
Right for "show me something before I type", wrong for the whole catalogue.

### 4. The rate limit is real, shared, and can break the widget

Six requests inside ~2 minutes returned **HTTP 429 with `retry-after: 55`**.
The agent already spends up to **4 calls per 60s tick** (crypto, gold, Toman, FX)
on the same public quota, from the same IP. **A search-as-you-type picker that
fires per keystroke will 429 the agent and blank MarketBox while the user is
choosing a ticker.** So: never fetch on keystroke — explicit submit or a long
debounce, an in-memory cache per query, and a 429 must degrade the *picker*
(a "try again in a moment" line), never the snapshot.

### 5. A retired id is silently dropped, not reported

`ids=bitcoin,this-coin-does-not-exist-xyz` → **200, one row**. All-unknown →
**200 `[]`**. Nothing in the payload says an id was ignored. Today
`MarketBuilder` files a missing crypto row under `omitted` → *"BTC unavailable"*,
which reads as "the source is down" when the truth is "this coin no longer
exists". With 43 curated ids that never happens; with 19,594 user-picked ids it
will. The build needs to tell the two apart.

## Found in passing: a shipped bug this feature would amplify

`MarketPriceFormatter.price` falls through to `%.4f` below 1.0
(`MarketBoxCore.swift:344`). Measured live today:

| ticker | price | renders as |
|---|---|---|
| SHIB | 5.47e-06 | `$0.0000` |
| PEPE | 3.57e-06 | `$0.0000` |
| BONK | 3.27e-06 | `$0.0000` |

**Three symbols already in the shipped curated list render as zero in v1.39**, and
a 50% move renders identically to no move. This is not caused by the lookup, but
the lookup takes the catalogue from 43 large caps to 19,594 coins where sub-cent
prices are the norm — so it stops being an edge case. Fix it here or record it as
a deliberate carve-out; do not ship a coin picker on top of a formatter that
prints zero.

## Affected files

| File | Change |
|---|---|
| `Shared/DeckSettings.swift:1085` | `tickers: [String]` gains an id-bearing shape + tolerant migration |
| `Shared/MarketBoxCore.swift:12` | resolver stops being the catalogue; `kind(for:)` needs a non-map crypto answer |
| `Shared/MarketBoxSnapshot.swift:263` | `fetchCrypto` joins stored ids directly |
| `Shared/MarketBoxCore.swift:220` | `MarketBuilder.build` — retired-id vs source-down |
| `Shared/MarketBoxCore.swift:329` | sub-cent price formatting |
| `DeckApp/DeckApp.swift:2472` | the twelve slot pickers become a searchable picker |
| new | `CoinSearchParser` + a host-side lookup/cache (app only, never the extension) |

## Open questions for the interview

1. **Migration.** 43 stored symbols → ids is a lookup the *old* map can do
   offline. Keep the map purely as a migration table, or resolve on first open?
2. **Picker shape.** The Credentials tab's searchable "Add Account…" sheet, or
   search inline in each of the twelve slots?
3. **Fiat and gold** stay curated (10 ISO codes + `GOLD`) — they are not
   CoinGecko rows at all. Confirm they keep their own list.
4. **Offline.** With no network the picker cannot search. Does a stored ticker
   still display its name, or degrade to the bare symbol?
5. **Scope of the formatter fix** — part of this unit, or its own?

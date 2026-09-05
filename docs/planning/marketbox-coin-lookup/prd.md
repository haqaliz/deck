# MarketBox Live Coin Lookup — PRD

**Slug:** `marketbox-coin-lookup` · **Type:** feat · **Branch:** `feat/marketbox-coin-lookup/aliz`
**Closes:** `ROADMAP.md:253-254` (MarketBox open follow-up).
**Probe:** `understanding.md` — every number below was measured live on 2026-09-05.

## 1. The ask, in one sentence

MarketBox can already *price* any CoinGecko coin but can only *name* 43 of them,
because settings store a bare symbol that the agent has to resolve through a
hand-written map — so store the coin's id instead and let a searchable picker do
the resolving.

## 2. The design hinge

`MarketSymbolResolver.cryptoIDs` (`Shared/MarketBoxCore.swift:16`) serves two
masters: the settings menu *and* the agent's fetch-time symbol→id lookup
(`MarketBoxSnapshot.swift:263`). The second is what caps the widget at 43 coins —
settings hold `tickers: ["BTC", …]`, so the agent needs a map to turn that into
`ids=bitcoin`.

**Store the id.** The picker becomes the only thing that resolves, the agent's
fetch becomes a plain join of stored ids, and the curated map stops being
load-bearing — it survives only as a migration table and an offline "Popular"
seed list (§5).

## 3. Front face

**No change.** Not one line of `DeckWidgets/MarketBoxWidget.swift` moves: same
rows, same three sizes, same day-change rule, same note line. `grep -rn
"tickers\|MarketSymbolResolver" native/DeckWidgets/` is clean, so the CLAUDE.md
trap *"two settings fields are read inside the widget extension"* does not apply.

Two things the user will see differently, both from the same rows:

- Coins outside the old 43 can appear at all.
- Sub-cent prices stop reading as zero (§7).

## 4. Back face (settings)

The twelve fixed `Ticker N` slots are replaced by a list you add to and remove
from — the Credentials tab's idiom, chosen in the interview.

```
Tickers
 ┌──────────────────────────────┐
 │ BTC   Bitcoin              ⊖ │   reorderable
 │ ETH   Ethereum             ⊖ │   (order = display order)
 │ USD   US Dollar            ⊖ │
 │ GOLD  Gold (1g)            ⊖ │
 └──────────────────────────────┘
           [ Add Ticker… ]
```

**Add Ticker… sheet** — one entry point, three sources:

- **Search** (crypto): debounced live search, results as `#rank  SYMBOL  Name`.
  Rank is shown **here only**, where it is fresh — a rank stored at pick time
  goes stale in the list (C5). This differs from the interview mock, which showed
  `#1` in the list itself.
- **Popular**: shown when the query is empty — the existing curated 43, **zero
  network calls**, so the sheet is instant and works offline.
- **Fiat & Gold**: the 10 curated ISO codes and `GOLD`. These are not CoinGecko
  rows and keep their own lists unchanged.

Reordering is a **phase-1 gate**, not polish (C6): the numbered slots gave order
for free and the list must not lose it. `.onMove` inside the settings `Form` if
it works on macOS, explicit ↑/↓ buttons per row if it does not.

Everything else in the tab (display currency, row count, day change, colors) is
untouched. `maxCount` stays 12. Adding at the cap disables **Add Ticker…** with
"12 is the maximum".

## 5. Data source (measured, and one endpoint rejected)

### Search — `GET /api/v3/search?query=`

**10.5 KB for "pepe", 25 coins, keyless, already ordered by market cap**, each
hit carrying `id`, `symbol`, `name`, `market_cap_rank`, `thumb`. Server-side
search means the catalogue is never held locally.

### Rejected: `/coins/list` — the endpoint the ROADMAP names

**1.24 MB, 19,594 coins, `{id, symbol, name}` only — no rank, no price**, and
**2,396 of 15,090 distinct symbols map to more than one coin** (`BTC` → 11,
`ETH` → 14, `PEPE` → 21, `GOLD` → 9; alphabetically `batcat` precedes
`bitcoin`). A symbol-keyed picker over it recreates the "blind-typed symbol"
problem the curated list was introduced to kill (`ROADMAP.md:240`).

### Rejected: `/coins/markets?order=market_cap_desc&per_page=250`

Works (197 KB, top 250 with rank) but is **unnecessary**: the curated 43 already
serve the empty-query state for free and offline. Recorded so it is not re-probed.

### The rate limit is shared with the agent, and it bites

Six requests inside ~2 minutes returned **HTTP 429, `retry-after: 55`**. The
agent already spends **up to 4 calls per 60s tick** (crypto, gold, Toman, FX) on
the same public quota from the same IP. **A picker that fires per keystroke will
429 the agent and blank MarketBox while the user is choosing a ticker.**

Policy, all of it pure and unit-pinned in `CoinSearchPolicy`:

| Rule | Value |
|---|---|
| Debounce after last keystroke | 600 ms |
| Minimum query length | 2 characters |
| Floor between requests | 2 s |
| Cache | per normalized query, app-process lifetime |
| In flight | one; a new query cancels the previous |
| On 429 | "Search is busy — try again in a moment." No auto-retry. |

The search runs **in the host app only**, on sheet interaction. Never in
`DeckAgent`, never in the extension, never on a timeline. A 429 degrades the
*picker*; it can never fail a tick or touch the snapshot.

## 6. Settings shape and migration

```swift
struct MarketTicker: Codable, Equatable {
    var symbol: String   // "BTC" — display, uppercased
    var name: String     // "Bitcoin" — cached so the list reads right offline
    var coinID: String   // "bitcoin"; empty for fiat and gold
    var rank: Int?       // market_cap_rank at pick time; display only
}
```

`kind` is **derived, never stored** — non-empty `coinID` → crypto, else `GOLD` →
gold, else fiat — so the two can never disagree.

**One symbol, one row** (C1). The list still dedupes by uppercased symbol, so the
face — which draws `Text(row.symbol)` and nothing else — can never show two rows
that read the same. Adding a coin whose symbol is already present is refused in
the sheet with *"PEPE is already in your list."*, never silently dropped. The
stored identity is the `coinID`; the symbol is what makes it unique in a list.

**Key:** the list is written to a **new** key, `tickerList`, and the legacy
`tickers` key is cleared on the first save. Reusing `tickers` with a new element
type would make an older Deck throw inside `MarketBoxSettings.init(from:)`, and
`DeckSettings.load()` falls back to `DeckSettings()` on *any* decode error — the
exact fault `ROADMAP.md` records as *"adding a widget silently reset every
setting"*. With a new key, a downgrade costs the MarketBox list alone (it falls
back to its four defaults) and nothing else.

**Migration**, in order, all tolerant:

1. `tickerList` present → use it.
2. else `tickers: [String]` (v1.26–v1.39) → map each through the curated table;
   a symbol it does not know becomes a ticker with an empty `coinID`, which
   still renders as `Unknown: X` exactly as today. No list is ever lost.
3. else `symbols` (the original free-text string) → the existing
   `normalizedSymbols(from:)` path, then step 2.
4. else the default four: BTC, ETH, USD, GOLD.

`DeckSettings.CodingKeys` is hand-written, and a forgotten case *compiles,
decodes as absent and never encodes* (CLAUDE.md; it cost every account once
already). `tickerList` must be added to `MarketBoxSettings.CodingKeys` and that
is pinned by a round-trip test.

## 7. Sub-cent prices — a shipped bug this feature would amplify

`MarketPriceFormatter.price` falls through to `%.4f` below 1.0
(`MarketBoxCore.swift:344`). Measured live today, **on symbols already in the
shipped curated list**:

| ticker | price | v1.39 renders |
|---|---|---|
| SHIB | 5.47e-06 | `$0.0000` |
| PEPE | 3.57e-06 | `$0.0000` |
| BONK | 3.27e-06 | `$0.0000` |

A 50% move renders identically to no move. With 43 large caps this is an edge
case; with 19,594 pickable coins sub-cent is the norm, so it ships here
(interview decision).

New rule, everything ≥ 0.01 unchanged:

| range | format | example |
|---|---|---|
| ≥ 1e9 / 1e6 / 1e3 / 1 | **unchanged** | `15.6B` · `$77,850` · `$1.75` |
| 0.01 ..< 1 | `%.4f` (unchanged) | `$0.5000` |
| 1e-9 ..< 0.01 | 3 significant digits | `$0.00000547` · `$0.0000175` |
| > 0 ..< 1e-9 | 2 significant digits, exponential | `$5.5e-11` |
| 0 | `$0.00` | |

Exponential below 1e-9 keeps the string short enough for a narrow row rather
than printing thirteen leading zeros.

## 8. Failure policy

### A retired or unpriceable id is silently dropped by CoinGecko

Measured: `ids=bitcoin,this-coin-does-not-exist-xyz` → **200 with one row**;
all-unknown → **200 `[]`**. Nothing in the payload says an id was ignored.

Today a missing crypto row lands in `omitted` → *"BTC unavailable"*, which reads
as "the source is down" when the truth is "this coin has no data". With 43
curated ids that never happens; with user-picked ids it will.

`MarketBuilder.build` therefore takes `quotesByID` as an **optional** (the `fx:
[String: Double]?` precedent) and splits the two:

| situation | crypto argument | bucket | note |
|---|---|---|---|
| no crypto tickers at all | `[:]` | — | (nothing to say) |
| crypto fetch attempted and failed | `nil` | `omitted` | `Crypto unavailable` (unchanged) |
| fetch succeeded, this id absent | populated | **`noData`** (new) | `No data: XYZ` |

**Three states, not two** (C2): `crypto` is already `nil` today both when the
fetch fails *and* when it was never needed (`MarketBoxSnapshot.swift:214`).
Conflating them would tell a user who owns only USD and GOLD that crypto is
unavailable.

**Never build an empty `ids=` request** (C3): measured, it answers 200 with the
top 100 coins (83.6 KB) rather than an error, which would render as the user's
list. `needsCrypto` means "at least one non-empty `coinID`", and `fetchCrypto`
returns `[]` without a request when its id list is empty.

"No data" rather than "Retired": CoinGecko also omits coins that still exist but
have no market data, and the payload does not distinguish them — the wording
must not claim more than the response supports.

### Offline

The stored `name` means the ticker list still reads `BTC Bitcoin` with no
network. The sheet's **Popular** tab is local and still works; search shows
"Search needs a connection." Existing rows keep rendering from the last snapshot,
unchanged.

## 9. Shell fit

- **Two data paths:** unchanged. MarketBox stays agent-pumped; this adds a
  *host-app-only* fetch on user interaction, which is not a third path — it is
  the same shape as the Credentials tab's Verify and the Azure project listing.
- **Settings in the app only:** unchanged. The extension reads the snapshot.
- **Anything the extension reads stays answerable from `settings.json` without a
  token:** unchanged — it reads neither key.
- **No Swift Charts** anywhere near a widget face (CLAUDE.md).
- **Loaders return pure data; views own layout:** `CoinSearchParser` and
  `CoinSearchPolicy` are pure; `HostCoinSearchLoader` joins them to `URLSession`
  beside the other `Host*Loader`s in `Shared/`.
- **Version bump** required for release, though no widget is *added* — v1.40.

## 10. Non-goals

- No free-text symbol entry. Tickers stay picked (`ROADMAP.md:240`).
- No fiat/gold catalogue growth — the 10 ISO codes and `GOLD` stay curated.
- No sparklines, no 24h % for fiat/gold (still needs a history source), no
  stocks or indices — all separate follow-ups.
- **No coin icons anywhere, including the sheet** (C7). Each `thumb` is its own
  request to `coin-images.coingecko.com` — 25 per search, against a feature whose
  central constraint is request budget.
- No change to display currency, row counts, colors, cadence, or the snapshot's
  shape beyond what §8 adds.
- No caching of search results across launches — in-memory only.
- No paid CoinGecko key, no API-key field.

## 11. Tests (XCTest, `DeckSharedTests`)

- **`CoinSearchParser`** — fixture `coingecko_search_pepe.json` captured from the
  live probe: 25 hits, rank order preserved, `market_cap_rank: null` tolerated,
  non-coin sections (`exchanges`, `nfts`) ignored, malformed → nil, `[]` → `[]`.
- **`CoinSearchPolicy`** — min length, debounce, the 2 s floor, cache hit/miss,
  429 → busy state with no auto-retry.
- **Migration** — `tickerList` wins; `[String]` maps through the curated table;
  an unknown symbol survives with an empty `coinID`; legacy `symbols` string;
  none → defaults; and a **round-trip** asserting `tickerList` actually encodes
  (the hand-written `CodingKeys` trap).
- **`MarketBuilder`** — `quotesByID: nil` → `Crypto unavailable`; present-but-id-
  missing → `No data: XYZ`; both at once; the existing collapse behaviour
  unregressed.
- **`MarketPriceFormatter`** — the three live values above, the 1e-9 / 0.01 / 1 /
  1e3 / 1e6 / 1e9 boundaries, zero, and the large-value cases unchanged.
- **Empty-ids guard** (C3) — no crypto tickers → no request; a crypto ticker with
  a blank `coinID` → no request. The top-100 response must be unreachable.
- **Duplicate symbol** (C1) — adding a second `PEPE` is refused, and the stored
  list never holds two rows with one symbol.

## 12. Risks

1. **The shared quota.** Mitigated by §5, but the picker and the agent do share
   an IP. Worst case is a busy line in the sheet; it cannot fail a tick.
2. **`/search` is undocumented in its ordering guarantees.** It returned
   rank-ordered results in every probe; the parser preserves server order rather
   than re-sorting, so a change in their ordering is a cosmetic difference, not
   a bug.
3. **Downgrade drops the MarketBox list** (§6). Deliberate, and the contained
   choice over resetting every setting.
4. **A 19,594-coin catalogue invites picking a scam token** with a real price and
   no liquidity. Rank is shown on every result row so the user can see what they
   are choosing; Deck takes no position beyond that.

## 13. Open questions

None outstanding. Three were resolved in the interview (2026-09-05): picker =
add/remove list with a search sheet; search = 600 ms debounce + cache; the
sub-cent formatter fix ships in this unit. Four more were resolved by the probe
rather than asked — the endpoint (`/search`, not `/coins/list`), the empty-query
state (curated 43, no network), offline naming (store `name`), and retired-id
wording (`No data:`).

---

## 14. Self-critique (2026-09-05)

Seven findings against the draft above. **Two are red** — the PRD as first
written would have shipped both. The body has been amended; this section records
what was wrong and why.

### 🔴 C1 — Nothing said what happens when two picked coins share a symbol

**2,396 symbols are ambiguous**, so a user can search "pepe" and add rank-56
`pepe` and rank-1055 `pepecoin-2`. Two problems collide:

- `MarketBoxSettings.normalized()` dedupes by **uppercased symbol**
  (`DeckSettings.swift:1147`), so the second pick is **silently dropped** — the
  user clicks Add and nothing appears.
- The face renders **`Text(row.symbol)` and nothing else** (`MarketBoxWidget.swift:202`)
  — verified, the `name` field is never drawn. So even if both were stored, the
  widget would show two identical `PEPE` rows.

**Fix (chosen): one symbol, one row.** Deduping stays by symbol, and the sheet
refuses a coin whose symbol is already in the list with *"PEPE is already in your
list."* rather than dropping it silently. Storage identity is still the `coinID`
— picking a different `PEPE` means replacing the one you have. This keeps §3's
promise that the face does not change; showing the name to disambiguate would
have broken it.

### 🔴 C2 — The builder and loader are still keyed on symbols

`MarketBuilder.build(symbols:)` calls `MarketSymbolResolver.kind(for: symbol)`,
which answers `.crypto` **only for the curated 43**. A newly picked coin like
`PURPE` returns `nil` → `unresolved` → every new coin renders **`Unknown: PURPE`
and no price**. The whole feature fails silently. The same map drives
`needsCrypto` / `needsGold` / `needsFiat` in `MarketBoxSnapshot.load`
(`:199-201`).

**Fix:** `build` and `load` take `[MarketTicker]`, and kind is read off the
ticker (§6), never re-derived from the symbol. Concretely:
`MarketBoxSnapshot.load(settings:)` → `MarketBuilder.build(tickers:)` →
`fetchCrypto(ids:)`, with the DeckAgent call site following. `kind(for: String)`
survives **only** for the migration table.

**And the crypto argument needs three states, not two.** §8 proposed
`quotesByID: [String: CryptoQuote]?` where `nil` means "the fetch failed" — but
today `crypto` is *also* `nil` when `needsCrypto` is false
(`MarketBoxSnapshot.swift:214`). Conflating them would report *"Crypto
unavailable"* to a user who owns only USD and GOLD. The three states are:
not attempted (`[:]`, no crypto tickers) · attempted and failed (`nil`) ·
succeeded (populated).

### 🟡 C3 — An empty `ids=` returns the top 100 coins, measured

`coins/markets?vs_currency=usd&ids=` answers **200 with 100 rows, 83.6 KB** —
the top 100 by market cap, not an error and not an empty list. Not reachable
today (the `needsCrypto` guard at `:199` blocks it), but the port to stored ids
adds a new way in: a ticker that is crypto-kind whose `coinID` is empty or
whitespace.

**Fix:** two belts. `needsCrypto` becomes "at least one non-empty `coinID`", and
`fetchCrypto` returns `[]` without building a request when its id list is empty.
Pinned by a test, because the failure is 83.6 KB of wrong data rendered as
though it were the user's list.

### 🟡 C4 — The fetch-error caption still watches the old key

`FetchStatusCaption(source: .marketbox, clearOn: settings.tickers.joined(...))`
(`DeckApp.swift:2498`). Left as is, the "we could not fetch" sentence would stop
clearing when the user fixes their list — the error line goes stale under a
control that no longer feeds it. **Fix:** `clearOn` joins the `tickerList` ids.

### 🟡 C5 — A stored rank is a stale rank

`MarketTicker.rank` is captured at pick time. A coin that was `#1` when added and
is `#40` today would display `#1` in the settings list indefinitely — a small
lie, in the one place the user goes to make a decision.

**Fix:** rank is shown **in the search sheet only**, where it is fresh by
construction. The ticker list row reads `BTC  Bitcoin` with no rank. *This is a
deviation from the mock approved in the interview, which showed `#1` in the
list* — raised at the review gate rather than changed quietly. `rank` stays in
the struct (it costs nothing and documents what was picked) but is not rendered.

### 🟡 C6 — Reordering must not be discovered late

Slot order *was* display order, for free, because the slots were numbered. An
add/remove list has no inherent order affordance, and `.onMove` requires a
`List`, which nests awkwardly inside the settings `Form` on macOS.

**Fix:** treat reordering as a **build-time gate in phase 1 of the plan**, not a
polish step. If `.onMove` does not work inside the Form, fall back to explicit
↑/↓ buttons per row. Shipping a list whose order cannot be changed would be a
regression against the twelve slots it replaces.

### 🟡 C7 — "if at all" is not a decision

§10 left coin icons as *"used in the picker sheet only, if at all"*.

**Fix: no icons in v1.** Every `thumb` is a separate request to
`coin-images.coingecko.com`, 25 per search, on a feature whose central constraint
is request budget (§5). Decided, not deferred.

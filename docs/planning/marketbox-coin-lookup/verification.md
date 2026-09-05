# Verification — MarketBox live coin lookup (2026-09-05)

v1.40, built Release, `scripts/lsclean.sh` run, installed to `/Applications`,
and driven with **Deck quit** — a running Deck overwrites both `settings.json`
and the snapshot with its in-memory copy (`pgrep -lf "MacOS/Deck$"` is the
check), so every result below came from
`/Applications/Deck.app/Contents/MacOS/DeckAgent` run directly.

## 1. The real upgrade path, against the real file

The installed container still held the **pre-migration** shape — no
`tickerList`, just `"tickers": ["CAD","ETH","USD","GOLD","AED"]` — so this is
the migration every upgraded install will take, not a synthesized one.

```
$ /Applications/Deck.app/Contents/MacOS/DeckAgent      # exit 0
  CAD    Canadian Dollar  163431.45159832377
  ETH    Ethereum         559601292.1800001
  USD    US Dollar        226002
  GOLD   Gold             32196938.747992862
  AED    UAE Dirham       61539.00612661675
  note: None
```

Five rows, all priced, no note, in IRT. The symbol array migrated to ids in
memory and nothing was lost.

## 2. The capability itself — a coin outside the curated 43

`PURPE` / `purple-pepe`, market-cap rank **1393**, is not in
`MarketSymbolResolver.cryptoIDs` and was **unreachable in v1.39** — there was no
way to name it. Written into `tickerList` alongside a deliberately dead id:

```
  ETH    Ethereum       2476.86
  USD    US Dollar      1
  GOLD   Gold           142.46307000819843
  PURPE  PURPLE PEPE    1.772e-05        ← impossible before this release
  note: 'No data: DEAD'
```

Two things proven in one run:

- **A coin outside the curated table prices.** This is the C2 regression: keyed
  on symbols, `kind(for: "PURPE")` answers nil and the row would have read
  `Unknown: PURPE` with no price.
- **A dead id says `No data: DEAD`, not "Crypto unavailable"**, while ETH keeps
  rendering. CoinGecko dropped the unknown id silently with a 200 (measured
  again here), and the build told the two apart.

## 3. Sub-cent formatting

`PURPE` came back at **1.772e-05**. Under v1.39's `%.4f` fallback that renders
`$0.0000`; under the new rule it renders `$0.0000177`. The three shipped
symbols that were already broken are pinned by unit test against values
measured live the same day: SHIB `5.47e-06`, PEPE `3.57e-06`, BONK `3.27e-06` —
all `$0.0000` before, `$0.00000547` / `$0.00000357` / `$0.00000327` after.

The formatted string is produced in the widget face, so this half is pinned by
`MarketSubCentPriceTests` rather than read out of the snapshot, which stores the
raw price.

## 4. Suite

`xcodebuild -scheme DeckSharedTests test` → `** TEST SUCCEEDED **` after every
phase, including the phases that changed existing expectations.

Three pre-existing tests were updated rather than deleted, each keeping its
original intent:

- `testEncodeDropsLegacySymbolsKey` → `…DropsBothLegacyTickerKeys`: the current
  shape is now `tickerList`, and **both** older keys must be absent.
- `testPartialCryptoFailureNamesTheSymbolNotTheKind` → `…NamesTheSymbolAsNoData`:
  the sentence changed because the meaning sharpened.
- `testEveryPickableSymbolResolvesToAKind` → `testEveryOfferedSymbolBecomesAUsableTicker`:
  same invariant (what the picker offers and what the loader prices can never
  disagree), now asserted against the path that actually runs.

## 5. What was **not** verified by hand

Stated plainly rather than implied:

- **The sheet's search was not clicked through.** The parser, the policy, the
  429 classification and the URL construction are unit-pinned, and one live
  `GET /search?query=purple%20pepe` returned 200; but the debounce, the
  duplicate refusal message, the offline copy and the reorder arrows were
  exercised only by their pure functions and a compile, not by a human clicking.
- **The widgets were not re-added from the gallery.** No widget was added or
  removed and the extension's own sources are untouched, so the descriptor
  cache is not implicated — but the house rule is to re-add and check all three
  sizes, and that is still outstanding.
- **The 429 path was observed during the probe, not against the shipped
  picker.** Six requests in ~2 minutes returned `429` with `retry-after: 55`;
  the sheet's handling of it is unit-pinned only.

The user's real `settings.json` was backed up before any of this, restored
afterwards (`["CAD","ETH","USD","GOLD","AED"]`, IRT), and Deck was relaunched.

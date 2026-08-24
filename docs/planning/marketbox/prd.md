# MarketBox — PRD

Slug: `marketbox` · type: `feat` · candidate: `ROADMAP.md:196` (last unshipped M5
widget) · brief: `docs/planning/_card/issue.md`

## 1. Restate the ask

A small glanceable widget showing a configured list of assets — crypto, fiat
(USD/CAD/…) and gold (1 gram) — all priced in **one global display currency** the
user picks: **USD, IRR (Iranian Rial), or IRT (Toman)**. Crypto rows carry a
24h % change and a 7-day sparkline; fiat and gold rows are price-only in v1.
Fetched by the agent every 60s; no API key anywhere.

## 2. User-visible spec

### Front face

- **Header line**: "MarketBox" title + the active display currency, always
  visible so the denomination is never ambiguous (e.g. `IRT`). A fetch-status
  chip line can sit under the header (same wording as WeatherBox).
- **Rows** (one per configured symbol, in order):
  - **symbol** — `BTC`, `USD`, `GOLD` …
  - **price in the display currency** — monospaced digits, abbreviated for very
    large magnitudes (Toman/Rial prices run into the billions): e.g. `15.5B` in
    IRT, `$77,262` in USD. The display-currency label is in the header, not
    repeated per row.
  - **24h change** — only for crypto: a colored arrow/dot (`↑ +1.0%` green,
    `↓ -2.4%` red, neutral grey for ~0). Fiat and gold rows show `–`.
  - **sparkline** — only for crypto, only on medium and large: a small 7-day
    line (downsampled from CoinGecko's 168-point series).
- **Sizes**: small = 2 rows (no sparkline) · medium = 4 rows (with sparkline) ·
  large = 8 rows (with sparkline). Counts clamped: `tickerCount` setting is the
  large count; medium shows at most 4, small at most 2 (rows would otherwise be
  clipped by the frame).
- **Unknown symbols**: rendered as a secondary line under the list —
  `Unknown: XRPX, FOO` — rather than a silent gap (user decision).
- **Empty / failing states** (reuse the fetch-status machinery):
  - no snapshot → `Add symbols in settings` chip + empty face;
  - fetch failed → existing FetchChip wording ("Can't reach Wallex" /
    "Can't reach CoinGecko" / "Agent hasn't run");
  - a snapshot always renders whatever it last has, even when stale.

### Back face (settings tab, in Deck.app)

All toggles pinned right, per deck convention:

- **Tickers** — text field, comma-separated symbols (e.g. `BTC, ETH, USD, GOLD`).
  Default `BTC, ETH, USD, GOLD` so a fresh widget is immediately useful (no
  tokens/privacy concern, unlike ShipBox/TaskBox). Empty → agent skips, records
  `.notConfigured`.
- **Display currency** — segmented picker: `USD | IRR | IRT`. Default `USD`.
- **Rows (large face)** — stepper `1…12`, default `8`.
- **Show day change** — toggle, default on. Applies to **crypto rows only**
  (fiat/gold always show `–`), so the face never implies a fiat/gold change it
  does not have.
- **Show sparklines** — toggle, default on. Applies to crypto rows on medium/large.
- **Colors** — `upColor` (default green), `downColor` (default red),
  `accentColor` (default blue, used for the header + neutral rows).

## 3. Data source

All four sources are **free, no key, JSON, no bot wall** (each verified with a
live probe on 2026-08-24, shapes recorded in `docs/planning/_card/issue.md`):

| Kind | Source | Endpoint | Gives |
|---|---|---|---|
| crypto | CoinGecko | `GET /coins/markets?vs_currency=usd&ids=<ids>&price_change_percentage=24h&sparkline=true` | price USD, `price_change_percentage_24h`, `sparkline_in_7d.price` (168 pts) |
| gold | gold-api | `GET /price/XAU` | XAU spot USD/oz → per gram ÷ 31.1035 |
| Toman anchor | Wallex | `GET /v1/markets` | `USDTTMN.stats.lastPrice` = Toman per USDT (free-market, e.g. 201,352) |
| fiat FX | open.er-api | `GET /latest/USD` | rates per 1 USD incl. CAD, IRR (for CAD row + any cross-fiat) |

**Conversion (pure, unit-tested):** let `TMN` = Wallex USDT→Toman rate; `D` =
display currency; crypto/gold USD prices from CoinGecko/gold-api; `CADperUSD` =
1 / rate[CAD].

- `D == USD`: crypto = CoinGecko USD price; `USD` = 1.0; `CAD` = 1/rate[CAD];
  gold = USD/g.
- `D == IRT`: everything × `TMN` (USD ticker = `TMN` itself; CAD = `TMN/rate[CAD]`;
  gold/g = USD/g × `TMN`).
- `D == IRR`: IRT × 10 (IRT = IRR ÷ 10, user-approved).

24h % and sparkline are **currency-independent** — taken as-is from CoinGecko,
never converted. Fiat/gold have no 24h%/sparkline in v1 (no free no-key history
source; Wallex exposes no klines; Yahoo is a flaky scrape — excluded).

**Approximation, stated honestly:** the Toman anchor is "Toman per USDT", and
USDT trades ≈ 1.00 USD (a small, stable peg error, well under the tick-to-tick
noise of the rate itself). Prices are converted by the agent at fetch time using
the current display-currency setting.

**Cadence & failure:** agent every 60s (standard). One block in
`DeckAgent/main.swift`:

- empty ticker list → record `.notConfigured`, skip;
- normalize symbols (uppercase, trimmed); resolve to kinds — curated crypto
  symbol→CoinGecko-id map, known fiat ISO codes, `GOLD`; anything else = unresolved;
- **fetch only what the tickers + display currency need**: CoinGecko (one call,
  only if a crypto ticker exists), gold-api (only if `GOLD`), Wallex (only when
  display ∈ {IRR, IRT}), open.er-api (only if a non-USD fiat ticker like `CAD`
  exists);
- **partial-failure policy** (PRBox-style "half a result is still worth
  reading"): a provider that fails contributes no rows, but if **some** rows were
  produced the snapshot is still written (`.ok`) and the failed/omitted reasons
  go into the snapshot's note line shown under the list; only if **no** row at
  all can be produced does the fetch record a classified outcome
  (`FetchClassifier`, new `FetchSource.marketbox`) — and the widget keeps
  rendering the last snapshot either way (snapshot only written on success, so
  last-good survives);
- unresolved/omitted symbols → collected into the snapshot, shown on the face
  (`Unknown: XRPX, FOO`), never fatal.

**Snapshot shape:** `MarketSnapshot` stores `writtenAt`, the `displayCurrency`
it was converted for, the rows, and the note line. The widget renders the
snapshot's prices and shows the **snapshot's** `displayCurrency` in the header
(not the live setting) — so a picker change mid-tick can never label rows with
the wrong currency; the header catches up on the next successful fetch (≤60s).

## 4. Shell fit

Reuses the agent-pumped path end-to-end, cloning the WeatherBox template:

- `DeckWidgets/MarketBoxWidget.swift` — clone of `WeatherBoxWidget.swift`
  (provider reads `MarketSnapshotStore.load()` + `DeckSettings.load().marketbox`,
  `FetchChip.text(source: .marketbox, …)`).
- `Shared/MarketBoxSnapshot.swift` — `MarketSnapshot`/`MarketRow` + store +
  `HostMarketLoader` + parsers (`CoinGeckoMarketsParser`, `WallexParser`,
  `GoldParser`, `FXRatesParser`) + pure conversion/formatters.
- `Shared/DeckSettings.swift` — `MarketBoxSettings` (tolerant decode) + `CodingKeys`
  + `DeckSettings` case.
- `Shared/FetchStatus.swift` — `FetchSource.marketbox` + `FetchClassifier` +
  `FetchStatusCopy.line/hint` cases.
- `DeckAgent/main.swift` — the fetch block (pattern of main.swift:117-198).
- `DeckApp/DeckApp.swift` — `MarketBoxSettingsView` tab + tab enum case + icon.
- `DeckWidgets/DeckWidgets.swift` — register in the bundle.
- `native/project.yml` — version bump `1.21 → 1.22` / `21 → 22` (WidgetKit caches
  descriptors per extension version; required for the gallery to show it).
- README.md, ROADMAP.md, `scripts/demo-data.sh` (sanitize the market snapshot).

**No shell invariants touched**: sandbox-safe snapshot, 60s cadence, settings in
the app only, single WidgetKit extension, three sizes. Deviations: none.

## 5. Non-goals

- No stocks/indices (explicitly out of scope for now).
- No fiat/gold 24h % or sparkline in v1.
- No per-ticker currency — one global display currency.
- No holdings/portfolio/total-value math.
- No key-based providers (no registration anywhere).
- No deep-links/tap-through to a coin page (follow-on).
- Not an order book / no trade signals.

## 6. Open questions

All answered by the interview; remaining items are plan-level:

- Exact abbreviation rule for huge Toman/Rial prices (e.g. `B`/`T` thresholds)
  — settle in the plan with the formatter tests.
- Whether the curated crypto symbol→id map starts small (BTC/ETH/TON/USDT/…) and
  grows, or is replaced by a live `/coins/list` lookup — plan decides (small map
  for v1, unknown symbols surfaced honestly).
- Whether the USD row, when display is IRT/IRR, additionally shows Wallex's own
  24h change of the Toman rate (`USDTTMN.stats.24h_ch`) — nice-to-have, plan decides.

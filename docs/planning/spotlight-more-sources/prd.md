# PRD + plan: spotlight-more-sources (ROADMAP M10, remaining items)

Stacked on `feat/spotlight-remote-search/aliz` (itself on the shell). Covers the
four remaining roadmap items in one branch, one commit per source:
PRBox, GitBox + CalBox, ShipBox + MarketBox.

## Honest scope line
Network sources (PRBox GitHub/Azure, MarketBox) are built and unit-tested on
**fixtures only**. Nothing here has been run against a live service: that needs
the user's tokens, which have not been approved for probing. Each source's
`verification.md` entry says what is unverified.

## New sources and their prefixes
| Source | Prefix | Searches | Kind | Needs prefix? |
|---|---|---|---|---|
| ShipBox runs | `run` | repo, workflow, branch, run number | instant (snapshot) | no |
| GitBox commits | `commit` | commit message, any age, in scanned repos | async (git subprocess) | **yes** |
| CalBox events | `cal` | title, location, notes; ±1 year | async (EventKit) | no; **off by default** |
| MarketBox | `mkt` | coin / stock name or symbol (live) | async (network, keyless) | **yes** |
| PRBox | `pr` | PR number, title, description | async (network) | **yes** |

**Why some need a prefix:** an unscoped query would otherwise send every typed
word to GitHub, CoinGecko and Yahoo at once, and spend the PRBox agent's 30/min
GitHub search budget and the shared CoinGecko/Yahoo IP quota (CLAUDE.md). Work
items already allow it (shipped); the rest stay opt-in per query.

## Shared layer change (first commit)
- `SearchProviderID` gains the five sources; "remote" becomes "deferred"
  (answered by the host asynchronously) with `requiresPrefix`.
- `TaskSearchCoordinator` is generalised to one runner per deferred source
  (own debounce, floor, cache, generation, rate-limit back-off), so a slow or
  failed source never delays another.
- `RemoteSearchFailure` gains `calendarAccess` and `noRepositories`.
- `SpotlightSettings` gains per-source toggles (calendar off by default).

## Per-source decisions
- **Runs:** search the snapshot ShipBox already holds ("recent runs"). A live
  query would cost ~11 KB per run per repo per search (CLAUDE.md); not worth it.
  Enter opens the run.
- **Commits:** `git log --all -i -F --grep=<text>` per discovered repo, capped,
  run concurrently with a timeout. Text is **one argument** after `--grep=`, so a
  query starting with `-` can never become an option (tested). Enter copies the
  short hash; Cmd-Return copies the subject.
- **Events:** EventKit predicate, 1 year back to 1 year ahead, the calendars
  CalBox uses. Enter opens the meeting link (`CalendarLink`, known hosts only)
  or copies the title. Off by default: titles on screen during a screen share.
- **Markets:** the existing `CoinSearch`/`StockSearch` loaders and
  `CoinSearchPolicy` floor. UA must stay the `URLSession` default for Yahoo
  (CLAUDE.md). Enter opens the coin / quote page (https only).
- **PRs, GitHub:** `search/issues` with `is:pr involves:@me <text> in:title,body`
  (any state), plus, for a bare number, a second request for the 100 most
  recently updated involved PRs filtered by number. **Number lookup therefore
  only covers recent PRs**, and the page says so.
- **PRs, Azure:** by id through the organisation-level pull request route; by
  title/description by listing recent PRs per project (`status=all`, `$top`) and
  filtering locally, because the list API has no text criteria. Unverified.

## Non-goals
Live GitHub Actions queries; searching PR comments or diffs; commit diffs
(`-S`); editing anything; searching NetBox/BatBox/LiveBox/WeatherBox.

## Order and gates
1. Generic layer (refactor; existing tests must stay green)
2. Runs   3. Commits   4. Events   5. Markets   6. PRs   7. Settings pages,
   examples, docs, verification, install
Every step: tests first and run red; full suite and a Release build green
before the commit; no widget file changes.

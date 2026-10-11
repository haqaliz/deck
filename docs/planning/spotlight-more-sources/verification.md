# Verification: spotlight-more-sources

Run 2026-10-10/11 on a Release build installed in /Applications, driven with
synthesised key events. The user's `settings.json` was backed up before each run
and not modified by the sources below.

## Automated
`DeckSharedTests`: 1671 tests, 0 failures. New suites: the generic layer
(prefixes, prefix-only rule, settings, failures, per-source pacing), builds,
commits (argument builder, parser, results, **integration against a real
temporary repository**), calendar events, markets, pull requests (GitHub query,
GitHub parser, Azure routes and parsers, results, partial-answer merge).

Mutation-checked (the guard was removed on purpose and the suite had to fail):
- GitHub quoting removed: **16** assertions fail.
- Commit `--grep=` wrapper removed: assertions fail **and git really writes an
  `--output=` file** (a stray file was found in the temp directory).
- Work-item grouping parentheses removed (earlier slice): 3 assertions fail.

## Measured on the running app
| Source | Result |
|---|---|
| Builds | `run ci` listed the user's real runs from `shipbox.json` (haqaliz/whetstone, belay, rereflect: Passed, Neutral, Running) |
| Commits | `commit spotlight` listed real commits of any age from the user's `~/dev` repositories, newest first (panel 640x437) |
| Markets | `mkt bitcoin` returned live CoinGecko and Yahoo results: Bitcoin (BTC) rank 1, then iShares Bitcoin Trust ETF (IBIT) interleaved, then ranked coins; ~4.5s from typing to results |
| Work items, no account | `bug login` still shows the WORK ITEMS block with "Choose an account for this in Credentials." after the move onto the generic layer |
| Agent/widget isolation | no reference to any search entry point from `DeckAgent` or `DeckWidgets`; no widget file changed |

## Verified live 2026-10-11 (search-live-probes)

Run against the real GitHub and Azure DevOps accounts
(`docs/planning/search-live-probes/probe.md`).

- **Pull requests — GitHub: verified.** `is:pr involves:@me "login"
  in:title,body` returned 11 rows; quoted terms AND-ed; `is:pr` drops issues
  (18 → 17); the 100-item recent pool backs the number lookup. **The
  fine-grained token does search** — the old `total_count: 0`
  (`prbox-review-state/probe.md:68-75`) was PRBox's `author:@me is:open`, not a
  token limit.
- **Pull requests — Azure: verified.** By-id returns the PR and 404s an unknown
  id; the list route's rows carry `repository.project.name` and map
  `completed`→merged / `abandoned`→closed; the deep link resolves. **Cost
  measured:** the list payload is ~0.5–0.6 MB and ~2 s **per project** (no
  server-side text criteria exists), so a words search is heavy but correct.
- **Work-item search (earlier slice): verified** — see
  `spotlight-remote-search/verification.md`. One fix came out of it: a typed
  `,`/`;` no longer makes the tag clause 400 the whole search.

## Still not verified

- **Calendar events**: off by default and not enabled in testing, so macOS was
  not asked for calendar access and no calendar was read. The EventKit path,
  the access prompt and the meeting-link action are unexercised.
- Opening a result (Enter) and copying a link (Cmd-Return) were not clicked for
  any of the new sources; the actions are unit-tested.
- A real 429, a bad token and a locked keychain as seen in the panel.
- Quick typing sending one request, and Esc cancelling a request in flight, on a
  network source other than markets.
- The settings page examples for the five new sources were built, and the page
  mechanics were checked for Clipboard earlier; the new rows were not looked at.

## Decisions worth knowing
- Builds search the snapshot ShipBox already holds ("recent runs"). A live
  Actions query costs ~11 KB per run per repository per search.
- A bare PR number only finds recent pull requests; older ones are found by words.
- Commits and calendar are "deferred" without being remote: a subprocess per
  repository and EventKit are too slow to run per keystroke.

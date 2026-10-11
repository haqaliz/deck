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

## NOT verified
- **Pull requests (GitHub and Azure DevOps): never run against either service.**
  Requests are built and parsed from fixtures that follow the documented shapes.
  Unknown: that `involves:@me` with `in:title,body` returns what the examples
  promise, that the number lookup through "100 most recently updated" behaves,
  the Azure by-id route's response and 404 behaviour, and that a project's list
  of 100 recent pull requests is a useful pool.
- **Work-item search (earlier slice): never run against Azure**, including the
  type filters (`IN GROUP 'Microsoft.*Category'`).
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

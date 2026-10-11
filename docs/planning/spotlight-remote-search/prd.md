# PRD: spotlight-remote-search

## Ask
Add a shared **remote-search layer** to the Spotlight panel and ship **TaskBox
search** as its first user: find any Azure DevOps work item, of any age and in
any state, by title, tag or id, from the panel.

## User-visible spec
- `task login bug`, or just `login bug` with no prefix (if tasks are enabled).
- Local sections still appear instantly. The **Tasks** section appears below
  them: "Searching…" while a request is in flight, then rows, then "No tasks
  found". A failure says why in one line (bad token, unreachable, rate
  limited) and affects only that section.
- A task row: title, then `Bug · Active · Project · #1234` and its tags.
- **Enter opens the work item in the browser; Cmd-Return copies its link.**
  Both go through `DeckLink.webURL` (the URL is built from remote data).
- Nothing is sent until the query has **2+ characters** and has sat for
  **300 ms**. A new keystroke cancels the request in flight; a late answer to
  an old query never replaces a newer one.
- A bare number also searches by id (`4521` finds work item 4521 and any title
  containing it).

**Settings (Spotlight tab, "Search in")**: a Tasks toggle with its example
(`task login bug`) and the caveat in plain words: *what you type is sent to
dev.azure.com, using the account TaskBox uses*. Default **on**; it does
nothing until TaskBox has an account. With the prefix and no account the
section says "Choose an account for TaskBox in Credentials."

## Data source
- Account: whatever `settings.taskbox.accountID` selects; resolved with the
  same `gate(.taskbox)` table the agent and settings window use, so `off`,
  `notConfigured` and `unavailable` (locked keychain) stay three different
  answers. The panel reads the keychain on the first remote query of a panel
  session, not when it opens.
- Query: WIQL through `WiqlClause.query(for:)` with
  `([System.Title] CONTAINS '<q>' OR [System.Tags] CONTAINS '<q>' [OR
  [System.Id] = N])` — **no `AssignedTo`, no state filter**, `$top` always,
  per project, then one org-scoped `workitemsbatch` for the rows. The user's
  text is a WIQL string literal: `'` is doubled, and the composed condition
  must pass `WiqlClause.validate` before any request.
- Cost: N projects = N+1 requests per search (CLAUDE.md: `workitemsbatch` is
  org-scoped). Only the debounced final query is sent.
- `System.Tags` is added to the batch fields; `TaskItem` gains an optional
  `tags` decoded with `decodeIfPresent`, so an existing `taskbox.json` and the
  widget are unaffected.

## The remote-search layer (pure, tested; reused by every later slice)
- `RemoteSearchPolicy`: minimum length, debounce, per-source floor between
  requests (500 ms), per-query cache (60 s), one in-flight request per source.
- `RemoteSearchState`: `idle | searching | results | empty | failed(reason)`
  per source, so a failure degrades one section.
- Result id namespacing per source (`task:{project}:{id}`): the project is
  part of the identity (CLAUDE.md).
- Host-app-only, on user interaction, never from the agent: a search must not
  spend the agent's rate-limit budget.

## Shell fit
- `SearchProviderID` gains `.task` (prefix `task`) — appended **after** `.oc`
  so local section order does not change.
- `SpotlightAction` gains `.open(URL)`; the panel runs Enter/Cmd-Return.
- `SpotlightViewModel` gains remote sections and a cancellable task; local
  results are still synchronous and never wait on the network.
- `SpotlightSettings` gains `taskEnabled` (tolerant decode, default true).
- README privacy table gains a row; CLAUDE.md gets what the probe measures.
- No widget is touched except `TaskItem`'s new optional field (Shared).

## Non-goals
PRBox, GitBox, CalBox, ShipBox, MarketBox search (later slices that reuse this
layer); browse mode; searching comments or descriptions; Jira or other
providers; caching results to disk; editing a work item from the panel.

## Open questions
None blocking; see the gating probe.

## Gating probe (before the plan is final)
Against the user's own Azure account, read-only, same calls Deck already makes
each minute: does `[System.Tags] CONTAINS` match as expected (it is a
semicolon-joined string field); latency and size of a broad term at `$top`;
what a quote, a `)` and `[` in the query do after escaping; whether
`workitemsbatch` returns `System.Tags`; whether a query returns closed and old
items. Written to `docs/planning/spotlight-remote-search/probe.md`.
**This uses the user's PAT, so it needs their go-ahead.**

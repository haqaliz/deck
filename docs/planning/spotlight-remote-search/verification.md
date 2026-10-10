# Verification: spotlight-remote-search (TaskBox search)

Run 2026-10-10. **The live Azure search has not been run**: it sends the
user's token and typed text to dev.azure.com, and the probe that was meant to
measure Azure's behaviour first (Phase 0) has not been approved. Everything
below that touches Azure's actual behaviour is therefore unverified.

## Automated
`DeckSharedTests`: 1544 tests, 0 failures (shell branch had 1486).
- Policy: normalise, 2-character minimum, 300 ms debounce, 500 ms per-source
  floor, rate-limit blocking, 60 s cache (empty answers cached, per-source,
  oldest evicted), stale-answer generation guard, failure wording.
- Query: user text is only ever a quote-doubled literal. 17 hostile strings, each
  also wrapped in text and doubled, must (a) pass `WiqlClause.validate`,
  (b) leave an identical skeleton once literals are removed, (c) keep exactly
  one project clause. **Mutation-checked:** removing the quote doubling fails 26
  assertions; the check helper itself is proven able to notice an escape.
- `TaskItem.tags` is optional; a `taskbox.json` written before it still decodes.
- A task row opens only through `DeckLink.webURL`; an unsafe URL is copy-only.
- The WIQL URL builder takes `$top`; search sends 26, the widget's URL is unchanged.

## Measured on the running app
- Tasks on, **no account**: `task login` shows a TASKS section reading "Choose
  an account for this in Credentials." and sends nothing. (Done by temporarily
  clearing `taskbox.accountID` in a backed-up `settings.json`, then restoring it.)
- Local sections are unaffected and still synchronous.

## NOT verified (needs the user's Azure account)
- That `[System.Tags] CONTAINS` and `[System.Title] CONTAINS` match the way the
  settings copy promises, including partial words and case.
- That closed and old items come back with no state filter.
- Latency and size of a broad term at `$top=26`.
- How Azure answers `'`, `)`, `[`, `]`, `%` after escaping (the tests prove the
  query's *shape*, not Azure's reply).
- That `workitemsbatch` returns `System.Tags`.
- A real token refused, a locked keychain, and a real 429, as seen in the panel.
- That quick typing sends one request, and Esc mid-flight cancels it.
- Opening a result (Enter) and copying its link (Cmd-Return) on a real row.
- The multi-project path (N+1 requests) on an account with several projects.

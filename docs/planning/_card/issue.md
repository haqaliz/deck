# Brief: search-live-probes (ROADMAP M10 follow-up)

Verify the Search panel's network providers against live accounts, then fix
whatever they contradict.

The M10 Spotlight/Search feature shipped (v1.49–v1.50) with five deferred
sources. Two network providers were built and fixture-tested but never run
against a live account:

- **Work-item search** (Azure DevOps, `task`/`bug`/`pbi`/… prefixes) —
  "never run against a live Azure account"
  (`docs/planning/spotlight-remote-search/verification.md:28-39`).
- **Pull-request search** (GitHub + Azure DevOps, `pr ` prefix) — "never run
  against either service" (`docs/planning/spotlight-more-sources/verification.md:29-37`).

ROADMAP.md:1077-1079 is explicit: run the read-only probes and "correct
whatever they contradict — type filters, `CONTAINS` on tags, the PR number
lookup, Azure by-id."

This is `dbf task search-live-probes`, chosen by `deck-next`.

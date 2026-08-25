# Understanding — ShipBox multi-repo

## What the work is really asking

ShipBox is a single-target widget: one `owner/repo` → one GitHub Actions fetch →
one snapshot → one flat list of runs. The ask is to fan that out over a small
list of repos while keeping **one** snapshot, **one** fetch-status key and one
readable face. The fetch itself is already proven — this is a shape change, not
a new data source.

## Affected files (all exist; nothing new is invented)

| File | Change |
|---|---|
| `native/Shared/DeckSettings.swift:484` | `ShipBoxSettings.repo: String` → a list + tolerant migration |
| `native/Shared/ShipBoxSnapshot.swift:10` | `ShipBoxSnapshot.repo: String` → repos; `ShipRun` gains a repo tag |
| `native/Shared/ShipBoxSnapshot.swift:69` | `HostGitHubLoader.fetch(repo:token:)` → fan-out + partial-failure policy |
| `native/Shared/FetchStatus.swift:19` | `.shipbox` stays one key; copy may need "N repos" wording |
| `native/DeckAgent/main.swift:130` | the guard (`repo.isEmpty`) and the `.notConfigured` branch |
| `native/DeckApp/DeckApp.swift:303` | `refreshShipBox()` mirrors the agent block exactly |
| `native/DeckApp/DeckApp.swift:1184` | settings tab: one `TextField` → a repo list |
| `native/DeckWidgets/ShipBoxWidget.swift` | header (`entry.repo`), row label, three faces |
| `native/SharedTests/ShipBoxSnapshotTests.swift` | parser/formatter/merge tests |
| `scripts/demo_data.py:102` | sanitizer writes `d["repo"]` — must follow the new shape |
| `README.md`, `ROADMAP.md` | registration + close `ROADMAP.md:311` |

## What the codebase already decided for us

- **Partial failure has a shipped precedent.** `HostMarketLoader.fetch`
  (`MarketBoxSnapshot.swift:193`) fetches each provider best-effort, keeps the
  first error, returns rows + a `note`, and throws **only when nothing at all
  could be built**. `MarketSnapshot.note` is rendered as one line on the face
  (`MarketBoxWidget.swift:165`). ShipBox should copy this verbatim: a repo that
  fails contributes no runs, the others still render, and the note names the
  failing repo.
- **Naming which target failed also has a precedent.** `PRChip.text`
  (`FetchStatus.swift:349`) composes two providers into one line: both-down-for-
  the-same-reason collapses to `"GitHub + Azure: <reason>"`, two different
  reasons become `"GitHub: <reason> +1 more"`. That is exactly the N-repo
  wording problem, already solved for N=2.
- **The settings migration has a precedent.** `MarketBoxSettings`
  (`DeckSettings.swift:770`) reads a legacy `symbols` key when `tickers` is
  absent, normalizes (trim/dedupe/cap) and **encodes only the new shape**. The
  `repo` → `repos` migration is the same three lines.
- **The tolerant-decode trap is documented.** `ROADMAP.md` "Fixed in passing":
  a non-tolerant decode silently resets *every* setting. `ShipBoxSettings`
  already has a hand-written `init(from:)`; the new key must join it.

## Ambiguities for the interview

1. **Merged stream or per-repo grouping?** A repo with busy CI can crowd every
   other repo out of a global newest-first list. Per-repo grouping fixes that
   and costs vertical space the small face does not have.
2. **Row label under multi-repo.** Today a row is `"<workflow> #<n>"` +
   `"<branch> · <duration>"`. Adding the repo makes three identifiers compete
   for one line at 11pt; something has to give, especially on small.
3. **Header.** `entry.repo` is the header today. With N repos it becomes what —
   a count, a rotation, the totals line alone?
4. **Repo cap.** ~5 was the deck-next suggestion; needs a number. It sets the
   settings UI (fixed slots vs add/remove) and the worst-case fetch time.
5. **Fetch concurrency.** No loader in the repo uses `async let` or a
   `TaskGroup` — MarketBox awaits four providers serially. Five repos × a 10s
   timeout is 50s serially, against a 60s tick. Concurrent fan-out is likely
   required, and would be the first in the codebase.
6. **Deep links.** `ShipRun.htmlURL` is parsed and unused (an explicit non-goal
   of ShipBox slice 1), but CalBox/TaskBox/PRBox rows became clickable in
   `5b0c417`/`a6ecd9c`. In scope here or not?
7. **Snapshot decode across the upgrade.** `ShipBoxSnapshotStore.load()` uses a
   synthesized decoder, so the first launch after the upgrade fails to decode
   the old `shipbox.json` and the widget shows "No build data" for one tick.
   Tolerate it or add a tolerant decode?

## Shell invariants checked (CLAUDE.md)

- **No Swift Charts.** ShipBox's face draws no chart today and must not start —
  a `Chart` in a widget face silently drops the widget from the gallery.
- **One timeline entry.** The CalBox archive-size lesson; ShipBox already emits
  a single entry with a 60s reload policy, and N repos must not change that.
- **Agent path only.** The widget sandbox has no network entitlement; every
  repo is fetched by `DeckAgent` (and mirrored by the host app's 60s timer).
- **Atomic writes / single writer.** `ShipBoxSnapshotStore.save` already goes
  through `AtomicFile`; the fan-out must still write **one** file, once.
- **Version bump.** Not a new widget, so no descriptor-cache risk, but a
  release bumps `1.27`/`27` in `native/project.yml` (three targets).

**No invariant is broken by this work** — it stays inside one widget, one
snapshot, one status key and the existing agent cadence.

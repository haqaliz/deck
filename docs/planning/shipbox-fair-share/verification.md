# shipbox-fair-share — verification record

**Date:** 2026-09-05 · **Installed:** v1.39 (`pluginkit -m -i com.deck.app.widgets` → `com.deck.app.widgets(1.39)`)

## What was verified

**Unit (1168 tests, all green, incl. 9 new `ShipBoxFairMergeTests` + 4 new
settings tests):** fairness (every repo's newest in the first `repoCount`
positions), round-robin order, globally-newest first element, intra-repo
order, tie stability, one-repo/empty degradation, and the
`ceil(runCount/repoCount)` page-sufficiency property.

**Live, against the real account (5 watched repos, static mode):**

| Setting | First 5 rows of `shipbox.json` | Verdict |
|---|---|---|
| `fairShare: true` | vocca, rereflect, belay, whetstone, deck — one per repo, each level newest-first | round-robin ✓ |
| `fairShare: false` | vocca×4, rereflect×4, belay… — global newest-first | toggle honored ✓ |

The first element is the globally newest run in both modes (vocca #138), so
the small face's `widgetURL` target is unchanged.

**Driving the agent directly** (`DeckAgent` with Deck quit, per CLAUDE.md):
the settings edit was honored on the next tick. One trap observed: a launchd
tick that started the same second as a manual `settings.json` edit wrote the
snapshot from the *pre-edit* settings — the toggle flip was verified by
running the agent alone, not by trusting a coincident mtime.

**Soak:** 20 full + 20 process + 5 overlap runs, 0 failures, container
restored by the trap (full 200×3 pass is the 24h-runbook scale).

## Not verified headlessly

- Re-adding ShipBox from the gallery and rendering at three sizes (UI
  action; the face is untouched by this change — only the snapshot's run
  order changes, which the live checks above exercised end to end).
- The full soak counts (runbook scale).
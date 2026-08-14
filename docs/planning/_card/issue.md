# Inline brief: ShipBox (build/deploy status)

Source: deck-next handoff (2026-08-14).

ShipBox — build/deploy status widget for the M3 slot (ROADMAP.md:48): GitHub
Actions runs for a configured repo, shown as a status list with colored dots
(pending/success/failure) + latest run summary, all three sizes.

Not local-first by design: fetch via DeckAgent-side HTTP like HomeBox's wttr.in
pump (docs/planning/_card/understanding.md:22-28), with a GitHub token pasted
in the ShipBox settings tab mirroring OpenBox remote (README.md:53-58) —
unauthenticated API rate limits are the caveat, so a token field is required,
not optional.

First slice: repo + runs list mapping (pure, TDD-able), then the widget front
face copying GitBox's staleness degrade and NetBox's colored-dot rows. No shell
invariants touched: new widget file, snapshot+store in Shared, settings struct
+ tab, agent append, register in README/ROADMAP.

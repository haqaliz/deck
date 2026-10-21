# bundle-identifier (card brief)

Source: `dbf task 77`, from the ROADMAP M9 item (#77) after the 2026-10-21
owner decision to stop waiting for the paid program.

## Brief

Flip `com.deck.app` / `com.deck.agent` → `io.github.haqaliz.deck*`. Everything in
`docs/planning/bundle-identifier/` except the flip itself has shipped: `DeckBundle`
is the single source, every call site reads it, `ContainerMigration` carries
settings, and `DeckBundleTests` pins the ids against `project.yml`, the generated
plists and `scripts/lib/ids.sh`.

The sequencing decision of 2026-08-28 tied the flip to the notarization release
so users would re-grant TCC once. **That release is deferred indefinitely**
(M9, owner decision), so the flip is done now instead: with no users there is no
migration pain, and the item stops blocking a future launch.

## Scope

`docs/planning/bundle-identifier/flip-runbook.md`, all four steps, except the
version bump (the release commit owns that) and the installed-copy gate, which
needs the owner's TCC re-grant.

Issue: https://github.com/haqaliz/deck/issues/77

# SMAppService for the LaunchAgents

Feature (M7 launch readiness). Move Deck's two LaunchAgents
(`com.deck.agent` 60s + `com.deck.agent.processes` 15s) from hand-written
`~/Library/LaunchAgents` plists to `SMAppService` registration so Deck appears
in System Settings → Login Items, where a cautious user looks first.

Context from `deck-next` (2026-08-27):

- M7 is the current milestone: "Deck is feature-complete for a public launch;
  what is missing is everything around the binary" (ROADMAP.md:317).
- Must ride the same release as notarization per
  `docs/planning/notarization/runbook.md:252-253`.
- Plan the migration from existing hand-installed plists (no double-running
  agents, no orphaned plists).
- Keep the General-tab uninstall button able to bootout the new registrations.
- Verify the agents still pump on their 60s/15s cadences and that DeckAgent
  runs correctly when launched via SMAppService.

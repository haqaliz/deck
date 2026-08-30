# Agent liveness check

**Type:** feat · **Slug:** `agent-liveness` · **Branch:** `feat/agent-liveness/aliz`
**Source:** inline brief (deck-next pick, 2026-08-30). No GitHub issue.

## The brief

Deck is blind to the third way its agents can be down: `SMAppService.status`
says a registration *record* exists, not that launchd loaded the job.

Measured on the dev machine (`docs/planning/bundle-identifier/probe.md`):

- `sfltool dumpbtm` → both agents `[enabled, allowed]`
- "Refresh in background" toggle → on
- `launchctl print gui/$(id -u)/com.deck.agent` → `Could not find service`
- nothing written for **6 hours**

`AgentReconcilePolicy` correctly does nothing here (intent `true`, state
`.enabled` → `[]`), and v1.34's notice cannot fire — that one is for
`[enabled, disallowed]` → `.requiresApproval`. This is the third distinct way
the agents can be down (never registered / user-vetoed / registered-but-
unloaded) and the only one Deck is blind to.

## The ask

Add a liveness check that compares `processes.json` mtime against
`livebox.processRefreshInterval` while `agentAtLogin` is on, and report it in
the **General** tab next to the existing Login Items notice. Recovery is the
documented toggle off→on.

`processes.json` is the right ground truth: it has been the fast agent's
**single writer** since v1.30, so its mtime separates "an agent ran" from "the
app ran" with no ambiguity. Every other snapshot is written by both, which is
why a dead agent is invisible while Deck is open.

## Why now

It is the named prerequisite for the held bundle rename —
`docs/planning/bundle-identifier/flip-runbook.md:11`:

> Ship the check … **before** this runbook, or the rename silently stops
> background refresh for the entire user base.

The flip puts *every* user into exactly this state, since the new agents
register only when the renamed app first launches.

## Known caveats (from deck-next)

- **`settings.json` is not a test seam.** With the record `.enabled`, the
  reconcile policy re-adopts `agentAtLogin: true` from the registration and
  never unregisters (CLAUDE.md trap 3).
- **The fault is expensive to induce.** The one measured way in is
  `launchctl bootout` of a *registered* agent while Deck is not running, and
  that leaves the job down until the next login or a toggle off→on cycle — smd
  does not reload it spontaneously (measured 2026-08-27).
- Keep the decision logic pure and unit-pinned like `AgentReconcilePolicy`;
  budget one hand-driven pass on the installed copy.
- **Must not fire on a fresh install** where no agent has run yet.

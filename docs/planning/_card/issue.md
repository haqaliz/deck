# Card — Heartbeat witness for the 60s agent

**Type:** feat · **Slug:** `agent-heartbeat` · **Branch:** `feat/agent-heartbeat/aliz`
**Source:** inline brief (`deck-next`, 2026-08-30). No GitHub issue.
**Follow-up from:** `ROADMAP.md` M7 agent-liveness entry — *"Open follow-ups: a
heartbeat witness for the 60s agent; distinguishing a corrupt `processes.json`
from an absent one (both read as 'never ran')."*

## The brief

Give the 60s agent (`com.deck.agent`) its own liveness witness.

Today `AgentLivenessPolicy` (`native/Shared/RefreshPolicies.swift:113`) reads a
single piece of evidence: the age of `processes.json`, which has been the *fast*
agent's (`com.deck.agent.processes`) single writer since v1.30. So a dead 60s
agent is invisible: eight widgets (OpenBox, GitBox, TaskBox, CalBox, PRBox,
ShipBox, WeatherBox, MarketBox) render stale data with an honest timestamp while
the General tab stays silent and the "Refresh in background" toggle stays on.

The scope was stated honestly when the liveness notice shipped rather than
fixed — the PRD says the notice "says 'background refresh has stopped' and never
names an agent", because the 60s agent has no unambiguous witness: the host app
writes everything it writes.

## What the work is

1. Write a heartbeat from the **full-role path only** (`DeckAgent/main.swift:54`
   already branches on `DECK_AGENT_ROLE` / `--processes`).
2. Extend `AgentLivenessPolicy` to **two witnesses**, so the notice can name
   which agent stopped instead of speaking about "background refresh".
3. While in the same code: separate a **corrupt** `processes.json` from an
   **absent** one — both read as "never ran" today.

## Caveats to design around

- **The host app writes every snapshot the full agent writes.** That is the
  reason the 60s agent has no witness today, and it is what the heartbeat must
  not repeat: it is only evidence if `DeckApp` never writes it. CLAUDE.md
  records the related trap — a running Deck silently overwrites the snapshot you
  are inspecting, and an **unchanged mtime** is the tell that a file was left
  alone.
- **`ContainerMigration` must not carry a stale heartbeat** into the renamed
  container. This is the exact shape of the bug the last cycle caught: a
  timestamp carried from the old install made a fresh registration read as
  "registered ten days ago, never ran", firing the notice falsely on the very
  release it exists to protect.
- **`AgentRegistrationClock`'s grace window has to cover both witnesses**, or a
  fresh install accuses itself.
- Verify on the **installed copy** — SMAppService cannot register from
  `build.noindex`.

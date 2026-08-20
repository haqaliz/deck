# Source brief: agent-fetch-status (inline, from deck-next handoff)

Make the agent-fetched widgets say *why* they're empty instead of showing one
generic "No X data" line.

Today `DeckAgent/main.swift:103,116` swallow every failure with `try?` and only
log, so `ShipBoxWidget.swift:128` ("No build data"),
`HomeBoxWidget.swift:143` ("No weather data") and `OpenBoxWidget.swift:176`
("No opencode data") render the same placeholder for bad token, bad repo,
offline, and genuinely-no-data.

Add an optional fetch-status (reason + lastAttemptAt) to the ShipBox / HomeBox /
OpenCode snapshots with tolerant decode (follow the `settings-schema-migration`
pattern), map it to a short human line in each widget's unavailable/footer view,
and TDD the pure error→reason mapping in `DeckSharedTests` first.

Source of the follow-up: `docs/planning/shipbox/prd.md:123` — "distinguishing
auth/404 fetch errors in the widget ('Check repo + token' vs 'No runs yet') —
slice 1 degrades both to the same unavailable state".

Caveats (from deck-next):

- The agent writes snapshots **only on success** today, which is what preserves
  the last good payload. A failure must keep the last good data and attach the
  status to it — never blank a widget that already has real data.
- Only GitHub distinguishes 401 vs 404 cleanly; wttr.in and `opencode serve` do
  not. Aim for a coarse three-way (not configured / auth or repo wrong /
  unreachable), not per-API precision.
- Ride-along if it stays small: the dead `OpenBoxSettings.refreshInterval`
  stepper at `DeckApp.swift:399` drives no code path (flagged in
  `docs/planning/livebox-process-cadence/prd.md:86`) — either wire it or
  remove it.

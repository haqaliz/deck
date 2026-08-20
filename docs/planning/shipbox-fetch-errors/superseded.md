# shipbox-fetch-errors — superseded

**Status:** superseded by `agent-fetch-status` (merged 2026-08-21, `9e5c8b7`).
Kept as a record so `deck-next` doesn't re-pick it.

Picked by `deck-next` as the recorded ShipBox follow-up
(`docs/planning/shipbox/prd.md:123`) and built on `feat/shipbox-fetch-errors/aliz`:
a `ShipFetchReason` enum with per-reason marker/title/hint, two optional fields
(`lastError`, `lastErrorAt`) on `ShipBoxSnapshot`, and a pure `ShipBoxFace.state`.

A parallel session shipped `agent-fetch-status` for the same user problem across
all three network-fetched sources. Its design won on two points:

1. **Status lives in its own file per source** (`fetch-{source}.json`), so a
   failure never rewrites the data file. That removes by construction the
   two-writer read-modify-write risk this branch could only narrow — the 🔴 in
   `critique.md` of the abandoned PRD.
2. **It covers ShipBox, HomeBox and OpenBox remote**, not ShipBox alone.

Ported forward onto it (`feat/shipbox-settings-status/aliz`): the settings-tab
echo, as `FetchStatusCopy.hint` plus a shared `FetchStatusCaption`, extended to
all three tabs.

Dropped with it: the per-reason marker/title/hint table (the chip copy covers
the face), the snapshot-carried error fields, and `ShipBoxFace.state` (the
availability rule it encoded no longer exists — data is never blanked on age).

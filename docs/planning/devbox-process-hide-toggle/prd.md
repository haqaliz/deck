# PRD — DevBox process hide toggle

Issue: #72 · ROADMAP M6 · 2026-10-21

## Problem

DevBox's open-ports list includes system daemons (`rapportd`, `ControlCenter`,
`Spotify`…) that the user never wants to see. The top-N cap limits the count but
not the noise: with four system rows and a cap of five, the one port that
matters is pushed out.

`docs/planning/devbox/prd.md:106` deferred this because "a hide toggle is a
fuzzy heuristic". The fuzziness is the design question, not a reason to skip it.

## What ships

A per-widget **hide list** in DevBox settings: command names whose port rows are
not drawn.

- Default empty → no behaviour change for existing users, no migration needed.
- Edit as a comma-separated field (the GitBox `repoPaths` pattern, already in
  this settings window), so there is no list-editor UI to maintain.
- Matching is **exact and case-insensitive** on `PortInfo.command`. A substring
  match would hide `node_exporter` when the user typed `node` — the fuzzy
  failure the PRD warned about.
- Filtered at render time (widget entry), not in the agent snapshot: the
  snapshot stays complete and the next feature (search, drill-down) sees
  everything.
- The PORTS counter follows the visible rows, so small/medium/large agree.

## Non-goals

- No container hide list (containers are named, not daemons; nobody asked).
- No effect on Spotlight search or any face other than the DevBox widget.
- No wildcard/regex/fuzzy matching. Exact names only.
- No agent or snapshot-schema change.

## Acceptance

1. Existing `settings.json` (no `hiddenCommands`) loads with an empty list.
2. `node_exporter` stays visible when the list contains `node`.
3. `Spotify` and `spotify` both hide `Spotify`.
4. A hand-edited `" Spotify "` (stray spaces) still hides `Spotify`.
5. PORTS counts and rows agree at all three sizes.
6. `DevBoxSettings` stays tolerant on decode (unknown/missing keys keep
   defaults).

## Tests

- `DevBoxSettingsDecodeTests`: empty default, explicit list, stray keys ignored.
- `DevBoxCommandFilterTests`: exact, case-insensitive, whitespace, non-substring.

UI wiring is verified by build + the existing settings-window smoke path.

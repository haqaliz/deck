# Inline brief: shipbox-inventory-pagination

Pagination + caching for ShipBox's automatic repo discovery: page the GitHub
inventory past 100 repos (`per_page=100`, cursor until empty) and cache the
discovered set across ticks so full inventory fetches stop happening every 60s
(~16 MB/hr instead of ~22).

Design the refresh rule carefully — a stale cache must not hide a repo that
just gained Actions, and a failed refresh must fall back to today's behavior,
both unit-pinned. Data path is proven (GitHub core API, 5000/hr budget); the
work is pure loader + pure policy, no shell, no face, no settings changes.

Measured numbers are in `docs/planning/shipbox-multi-repo/`.

## Source

`deck-next` handoff, 2026-09-13. ROADMAP M8 follow-up entry:
"ShipBox: inventory pagination + caching — paginate the repo inventory past 100
repos and cache the discovered set across ticks (~16 MB/hr instead of ~22), the
two open follow-ups from the multi-repo entry."
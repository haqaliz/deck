# Issue: OpenBox remote incremental sync

Source: `deck-next` handoff (`dbf feat openbox-remote-incremental-sync`).

OpenBox remote mode refetches every session's full message list, `parts`
included, every 60s tick — the known-risk note in
`docs/planning/openbox-remote/prd.md:102-105`. Add a limit-based incremental
sync to `RemoteOpenCodeMetricsLoader`: a per-session cursor carried in the
snapshot, fetching only messages newer than it, with a full-resync fallback on
cursor miss and on server versions that lack the `limit` param (probe
`/session/{id}/message` on the live server first). Keep the existing
aggregation and outcome classification intact — `DeckSharedTests` already pins
the loader, so the slice lands testable. No face, settings or snapshot changes;
the shell stays untouched.
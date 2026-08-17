# LiveBox disk per-volume (inline brief)

Give LiveBox a disk per-volume slice: enumerate mounted volumes
(statfs/getmntinfo or the Volume resource API already used in
`native/DeckWidgets/Loaders/SystemMetrics.swift:126`) and show each volume's
used-percent + free space as rows/bars, while small/medium faces keep the
aggregate DISK row. Scope out duplicate APFS volumes (e.g. `/System/Volumes/Data`)
and decide the large-face layout (per-volume bars vs. keeping the aggregate
chart line). Add settings (toggle + per-volume color optional) following the
LiveBoxSettings tolerant-decode pattern, and keep everything in the
self-sampled in-widget path — no agent changes. Finish by registering in
README.md and ROADMAP.md and verifying all three sizes from the Widget Center.
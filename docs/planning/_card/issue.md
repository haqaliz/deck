# NetBox threshold coloring (inline brief)

Give NetBox the warn/alarm threshold coloring LiveBox already has (copy the
pattern from the LiveBox widget + its warnThreshold/alarmThreshold settings,
`native/Shared/DeckSettings.swift:91`): metric rows and the history chart turn
amber/red when up/down rates cross the per-rate thresholds, with a NetBox tab in
the Deck app settings. All math lives in `Shared/NetBoxCore.swift` (rates() at
:51, formatRate at :81) so write the threshold + coloring logic in Shared with
DeckSharedTests coverage, mirroring how LiveBox's thresholds were done. Two
caveats from ROADMAP.md:82 / the interface picker work: apply thresholds to the
resolved (pinned-or-auto) interface only, and treat zero/stale rates as "no
reading", not "below threshold". Finish by registering the feature in README.md
and ROADMAP.md and verifying all three sizes from the Widget Center.

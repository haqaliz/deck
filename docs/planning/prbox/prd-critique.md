# PRBox PRD — self-critique

Pressure-tested against the shell invariants, the probe data, and the code the
PRD claims to reuse. Two 🔴, seven 🟡.

## 🔴 R1 — Azure counts are capped by `$top`, so the header lies

§2 says `MINE`/`REVIEW` are uncapped totals that "can exceed the rows", and §4
model comments repeat it. That works for GitHub — `/search/issues` returns
`total_count` independent of `per_page`. **It does not work for Azure**: the
probe payload has only `count` (rows returned) and `value`; there is no total
field. With `$top=<cap>` the Azure half of every count silently saturates at the
row cap, so "3 MINE" could mean 3 or 30.

**Fix:** call Azure with `$top=101` (not the row cap), count the filtered rows
locally for the header, then trim to `prCount` for storage. If a role returns
exactly 101, render the count as `100+`. Add a test: 101 fixture rows → header
`100+`, stored rows == cap.

## 🔴 R2 — `DeckSettings` top-level registration is unstated, and this exact omission has shipped a data-loss bug before

§5 lists the enum widenings but never says that `DeckSettings` itself must gain
`prbox = try c.decodeIfPresent(PRBoxSettings.self, forKey: .prbox) ?? PRBoxSettings()`.
`ROADMAP.md` ("Fixed in passing") records that adding a widget section without
this silently reset **every** setting — colors, tokens, repo paths — for anyone
whose `settings.json` predated it, then overwrote the file on the next save.
Three regression tests pin the current behaviour.

**Fix:** make it an explicit PRD requirement with its own test — decode a
`settings.json` that has no `prbox` key and assert every *other* section
survives intact.

## 🟡 A1 — `prCount` range contradicts the per-size row counts

§2 says medium ≤3 rows, large ≤8, then defines `prCount` as 3…12. What does 12
mean on large, or 3 on medium?

**Fix:** `prCount` is the **large** row count, range 3…12, default 6; medium
renders `min(prCount, 3)`. Say so.

## 🟡 A2 — The composed chip is hand-waved, and it is the one genuinely new piece of logic

§7's table ends with "the GitHub line, with `+1 more` appended", which is a
phrasing, not a rule, and it ignores `FetchChip`'s "agent hasn't run" case —
with two sources that fires twice and must collapse to one line.

**Fix:** specify a pure `PRFetchChip.text(github:azure:githubEnabled:azureEnabled:dataWrittenAt:now:)`
returning `String?`, with an explicit precedence: agent-silent > both-failed >
one-failed (named) > none. Both-failed with the *same* outcome reads
`"GitHub + Azure: can't reach"`; with different outcomes, name the GitHub one
and append `"+1 more"`. Unit-test the matrix — it is pure and cheap.

## 🟡 A3 — Disabling a provider leaves its stale failure on screen

Both providers default off, and a user who turns one off after a bad token
leaves a `.authOrTarget` status file behind. `FetchStatusStore` has **no
`clear`** (`FetchStatus.swift:250-282`) — only `record`.

**Fix:** when a provider is disabled, the agent records `.ok` for that source,
which renders nothing. This is the existing precedent: OpenBox local mode
clears a stale remote failure the same way (`DeckApp.swift:~113`).

## 🟡 A4 — "read-only Code (Read) is enough" is asserted, not measured

§3's Azure caption claims a Code (Read) PAT suffices, but the probe ran with an
existing PAT of unknown scope, and the flow also calls `_apis/connectionData`.

**Fix:** either verify with a freshly minted Code (Read) PAT before the caption
ships, or soften to "a read-only PAT that can see Code is enough" and drop the
scope name. Do not ship a scope instruction that has not been tested — a user
who follows it and gets 203-plus-HTML has no way to know the doc was wrong.

## 🟡 A5 — Dedupe key unspecified

§4 says an authored+reviewing PR collapses to one `.authored` row (correct —
Azure *does* let you be a reviewer on your own PR, and the `vote == 0` filter
would keep it). The key is not stated, and titles are not unique.

**Fix:** dedupe on `(provider, repo, number)`. Test with a fixture where the
same PR appears in both role queries.

## 🟡 A6 — Relative age reinvents an existing formatter

§2's `2h` / `10d` ignores `OpenBoxCore.relativeTime(from:to:)`
(`OpenBoxCore.swift:199`), which already produces `just now` / `10m ago` /
`2h ago` / `3d ago` and is already tested.

**Fix:** reuse it, or state why the row needs the suffix-less variant (it
does — `10d ago` in a right-aligned column is noise). If a new one is written,
put it beside the old one and test both, rather than leaving two spellings of
"how long ago" in `Shared/`.

## 🟡 A7 — Host-app refresh path omitted

§5 lists the agent but not `refreshPRBox()` in `DeckApp`'s `onAppear` **and**
its 60s timer — every agent-pumped widget has both, and without it settings
changes do not show until the next agent tick.

**Fix:** name it, and confirm the write goes through `AtomicFile` (the M4
crash-robustness invariant) since app and agent both write `prbox.json`.

## Checklist

| Question | Verdict |
|---|---|
| Front face ≤5 elements at a glance | ✅ two counts + rows |
| Back-face settings + sane defaults | ✅ (both providers off by default) |
| Data source real, fallback defined | ✅ probed live; empty states split from failures |
| Cadence fits the data | ✅ 60s, matches the shell |
| Reuses the shell without touching invariants | ✅ two enum widenings only |

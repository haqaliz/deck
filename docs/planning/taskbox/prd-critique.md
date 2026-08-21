# TaskBox PRD — self-critique (Phase 4)

Pressure-tested against the shell invariants in CLAUDE.md and the ShipBox /
HomeBox precedents. §9 of the PRD already carries R1, R2 and C1–C5; this file
is what a second read found **on top of** those.

## 🔴 Red

### N1 — Fixtures would leak the employer's work-item titles

PRD §9 R1 step 2 says "record the actual payloads as test fixtures". Those
payloads are real Azure DevOps work items from org `Manifold` — titles,
iteration paths and the PAT owner's display name — committed to a public-ish
git repo. That is the user's employer's data, and no existing fixture in
`SharedTests/Fixtures` contains anything like it.

**Fix:** the live `curl` is a **shape-discovery** step whose output is read and
then discarded. Fixtures committed to the repo are **synthetic**, hand-written
to the shape the curl revealed. §9 R1 step 2 must say so explicitly, and the
plan must not create a task that pastes a raw response into a file.

### N2 — "Always write" vs "skip if unchanged" is unspecified

`DeckAgent` has two write idioms and the PRD picks neither. GitBox/DevBox skip
when `snapshot == stored`; ShipBox/HomeBox/ClipBox always write, with a comment
saying `writtenAt` drives the staleness window. TaskBox's face **has** a
staleness hint (`entry.stale`, `· HH:mm` past 5 min), so skipping the write on
a quiet day would make a perfectly healthy widget claim to be stale.

**Fix:** TaskBox **always writes** on a successful fetch, with the same comment
the ShipBox block carries. State it in §3 and in the plan's agent task.

## 🟡 Amber

### N3 — `≤7d` is hardcoded in the spec's example strings

§2 shows `"3 overdue · 7 due ≤7d"` with a literal 7, but `soonWindowDays` is a
1…30 stepper. The label must interpolate: `"… due ≤\(soonWindowDays)d"`.
Trivial, but it is exactly the kind of thing that ships hardcoded. Add a
`countsLine` test case at a non-default window.

### N4 — The batch call fails wholesale on one deleted id

`workitemsbatch` returns an error for the entire request if any requested id is
inaccessible or was deleted between call 1 and call 2 — a real race at a 60s
cadence. The API has an opt-out that the PRD's request body omits.

**Fix:** add `"errorPolicy":"omit"` to the batch body (§3, call 2) so missing
ids are skipped and the rest still render. Worth a line in §3 explaining why.

### N5 — `project` is not percent-encoded

§7 says `organization` is normalised, and says nothing about `project`. Azure
DevOps project names may contain spaces. An unencoded space produces a
malformed URL and a `.badResponse` chip that blames the server for a client
bug.

**Fix:** both `organization` and `project` are trimmed and
`addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)`-encoded, and
either being empty after trimming throws `.invalidTarget`. Mirror
`HostGitHubLoader.makeURL`. Test both.

### N6 — Header scope: snapshot or settings?

§2 says the header shows `"{org} / {project}"` but doesn't say from where. If
it reads settings, changing the project makes the header claim data it isn't
showing until the next tick.

**Fix:** the header reads `snapshot.scope` — what the data *is*, not what it
*will be*. ShipBox does exactly this with `snapshot.repo`. One-line
clarification to §2.

### N7 — `itemType` is stored but never rendered

Dead weight unless justified. Same situation as `url`, which §6 explicitly
covers as stored-not-rendered.

**Fix:** keep the field (it is cheap, and a Bug/Task distinction is the obvious
next iteration) but say so in §6 alongside `url`, so a reviewer doesn't read it
as an oversight.

### N8 — Placeholder content

`ShipBoxProvider.placeholder` returns plausible fake runs. TaskBox's must use
obviously-synthetic titles, not anything resembling a real work item, since the
placeholder is what the gallery preview shows to anyone looking at the screen.
Minor, but name it so it isn't filled in from the curl output.

## ✅ Held up

- No shell invariant is touched — verified against CLAUDE.md's list.
- The agent-pumped path, `FetchStatus` reuse and settings-window-only rule all
  match the ShipBox precedent exactly.
- The provider-agnostic model (`id: String`, `provider`) genuinely absorbs
  GitHub Issues / Jira / Linear without a reshape.
- The all-undated face (§2, §9 R2) is the right answer to the headline risk.
- 203-not-401 (C2) is a real Azure DevOps behaviour and is caught before it
  produces wrong copy.

## Net

Eight additions, two of them red. **N1 is the one that matters** — it is a data
handling mistake, not a design one, and it is easy to make while "just capturing
a fixture". N2 and N4 are correctness. N3, N5–N8 are small and cheap.

All eight fold into the PRD before planning; none change the architecture.

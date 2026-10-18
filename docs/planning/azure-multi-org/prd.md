# PRD — Azure DevOps multi-org (TaskBox + PRBox)

Slug: `azure-multi-org` · Branch: `feat/azure-multi-org/aliz` · 2026-10-19

## 1. The ask

Let TaskBox and PRBox pull from **more than one Azure DevOps organization** in the
one list they already build. Today one `CredentialAccount` is exactly one
organization carrying up to eight projects
(`native/Shared/CredentialAccount.swift:153-160`); spanning orgs means spanning
*accounts*.

This is the recorded "natural next slice" from
`docs/planning/azure-multi-project/prd.md:185-187` and the last open follow-up in
the TaskBox/PRBox entry (`ROADMAP.md:165`, `:212`, `:433`). Every sibling has
shipped: multi-project (`:401`), the 5→8 project cap (`:907`), review state
(`:194`), custom WIQL (`:926`) and presets (`:957`).

## 2. Decided in the interview (2026-10-19)

The first interview answer was "an organization list on the account". **A blocker
discovered before the PRD was written invalidated it** (§3), so the design was
re-opened and the fallback — the previously-declined "slot that binds several
accounts" — is the one that shipped here.

| Question | Decision |
|---|---|
| Mechanism | **The Azure slot binds several accounts** (design C). Each account stays exactly what it is: one organization, its projects, its own PAT, one keychain item. |
| Cap | **4 accounts** per slot (`AzureAccountBinding.maxAccounts`). Inherited from the interview's "4 organizations": one account ⇔ one org. |
| Scope of the change | **`.taskbox` and `.prboxAzure` only.** `openbox`, `shipbox`, `prboxGitHub` stay single-account. |
| TaskBox header | One account → today's wording exactly. Several accounts → **"N orgs"**. |
| Sprint chip / team picker | Rule unchanged: offered only when there is **exactly one target** (one account, one project). Relaxes to multi-account correctly on its own. |
| Rows | TaskBox row id stays the numeric work-item id; **PRBox's row id and dedupe key gain the organization** (§6). |
| Verify | Unchanged: per account, org-level `connectionData`. |
| Search | The `wi`/`pr`/`bug`… sources iterate the bound accounts, host-app-only, under the existing policy. |
| Merge | Pure functions merge per-account results — the same shape `PRSnapshotBuilder` already uses to merge GitHub + Azure. |

## 3. Why the org-list design was rejected (the blocker)

**A PAT is organization-scoped, so one account's one token cannot authenticate to
a second organization.** Evidence from Microsoft Learn, *Use personal access
tokens*, updated 2026-09-21:

- Creation: *"Enter a name, **select one organization**, and set an expiration
  date."*
- Guidance: *"use an **organization-scoped** PAT with the minimum scopes…"*
- **Retirement: *"Azure DevOps is retiring global PATs. All existing global PATs
  stop working on December 1, 2026."*** A **global** PAT (`allOrgs`) was the only
  kind that crossed orgs — so the org-list design would have worked for six weeks
  and then broken for everyone.
- *"When an account is disabled or removed from an organization, its PATs can no
  longer access **that organization's** resources."*

Deck is PAT-only by decision (`docs/planning/taskbox/prd.md:292`: "No OAuth /
Entra ID"), so an Entra token — which *can* span orgs where the identity is a
member — is out of scope. Therefore multi-org ⇒ multiple credentials ⇒ the slot
binds several accounts.

`ROADMAP.md:433` already said multi-org "needs a slot that binds several
accounts"; this PRD confirms why that was not a preference but the mechanism.

## 4. What design C changes (model)

| Piece | Today | After |
|---|---|---|
| `TaskBoxSettings.accountID: String?` (`DeckSettings.swift:930`, struct at `:918`) | one | `accountIDs: [String]` |
| `PRAzureSettings.accountID` (`:1120`, struct at `:1116`) | one | `accountIDs: [String]` |
| `DeckSettings.accountID(for:)` / `setAccountID` (`:306-324`) | single | add `accountIDs(for:)` / `setAccountIDs(_:for:)`; keep the singular for the three single slots (returns `.first`) |
| `DeckSettings.account(for:)` (`:329-333`) | one | add `accounts(for:) -> [CredentialAccount]` (kind-checked, dangling dropped) |
| `DeckSettings.gate(_:unavailable:)` / `CredentialGate.fetch` (`CredentialsMigration.swift:79-130`) | one credential | **`.fetch` carries a non-empty list**; single slots are a list of one |
| `CredentialsMigration.migrate` (`:211-213`) | assigns one id | assigns a one-element list |
| New policy | — | `AzureAccountBinding` in `Shared/`: `normalise` (trim, de-dup, drop empties, cap 4, order preserved — the `AzureAccountProjects` shape) and `setSlot`, applied at decode, the gate and each loader call site |

**Tolerant decode / one-way migration**, exactly the `projects`/`project`
pattern (`CredentialAccount.swift:199-207, 220-224`): decode `accountIDs` when
present, else wrap the legacy `accountID`; **encode writes only `accountIDs` and
omits `accountID`**, so the dead field cannot keep answering. A file carrying
both is a hand-edit and the plural wins outright.

**🔴 This is not implementable by adding a property.** `TaskBoxSettings`
(`DeckSettings.swift:918-990`) and `PRAzureSettings` (`:1116-1142`) hand-write
only `init(from:)`; their `CodingKeys` and `encode(to:)` are **synthesized**, so
a new `accountIDs` alongside `accountID` would be decoded tolerantly and then
**both written back**. The legacy key exists in `CodingKeys` only as long as the
property does, and removing the property removes the key the decoder needs. The
fix is the `CredentialAccount` shape: **hand-written `CodingKeys` carrying both
keys, plus a hand-written `encode(to:)` that omits `accountID`** — and a
round-trip test for *every* field, because this is exactly the
hand-written-`CodingKeys` trap CLAUDE.md records (a forgotten case compiles,
decodes absent and never encodes).

**Gate precedence** (must reproduce today's four answers when the list has one
element — that is the regression bar). One rule table, not two: `gate` returns
the list form for **every** slot (single slots are a one-element list) and a
`single` convenience serves the three single-slot callers, so the host and the
agent can never drift.

1. empty list → `.off`
2. ≥1 account resolves with a usable target → `.fetch(resolved)` (partial is an
   answer, like a provider that failed). **Every bound account that did not
   contribute — failed or keychain-`unavailable` — is named in the snapshot
   `note`**; silence about a bound account is the C1 mistake.
3. otherwise, ≥1 selected id is in `unavailable` → `.unavailable`
4. otherwise → `.notConfigured`

The single `FetchSource` key per slot (`.taskbox`, `.prboxAzure`) is unchanged —
multi-project already settled that a slot has one chip, and multi-org must not
multiply it.

## 5. Cost (arithmetic, not measurement)

Per account the loaders are unchanged — one org, its projects. Across N bound
accounts (each `org` with `P` projects):

| Call | Scope | Cost |
|---|---|---|
| `wiql` (TaskBox) | project | N×P |
| `workitemsbatch` (TaskBox) | **org** → one **per account** | N |
| `connectionData` (PRBox) | **org** → one **per account** | N |
| `git/pullrequests` (PRBox) | project | 2×N×P |

At the cap (4 accounts × 8 projects): TaskBox 32 WIQL + 4 batches; PRBox 4
identity + 64 queries — all in the existing `withThrowingTaskGroup`. **This is
arithmetic; nothing above 5 projects on one org has been measured
(`azure-project-cap/prd.md`), and nothing here is.** Each account's fetches run
concurrently; accounts are fetched concurrently too, so the wall-clock is the
slowest account-plus-merge, not the sum.

**The Search panel shares these loaders and fans out over the same bound
accounts** (`AsyncSearchCoordinator`), under the existing `RemoteSearchPolicy`
(debounce, per-source floor, per-query cache, host-app-only). A `pr ` search
across 4 accounts × 8 projects is 64 project queries per debounce — the cap makes
it bounded, and a 429 still degrades only the one section.

## 6. Correctness bugs multi-account introduces

Each is a wrong face if unaddressed — not polish.

**6.1 🔴 PRBox dedupes rows without the organization.**
`PRFormatting.deduped` keys on `(provider, repo, number)`
(`PRBoxSnapshot.swift:219-240`) and `PullRequestItem.id` is
`azureDevOps:{project}/{repo}#{number}` (`AzureDevOpsLoader.swift:949`). Two orgs
each with an `api` repo and PR #12 collapse to one row — the *same* class of bug
multi-project fixed by adding the project. **Fix:** the id becomes `azureDevOps:{org}/{project}/{repo}#{number}` **and** the
dedupe key gains the org. Concretely: `PullRequestItem` gains a tolerant
`organization: String?` (nil for GitHub and for rows written before it existed),
`deduped`'s `Key` and `sorted`'s tiebreak include it, and the id interpolates it.
The parser already has the org in hand (`target.organizationName`,
`AzureDevOpsLoader.swift:927-966`).

**6.2 🟡 The TaskBox header would name one org as if it were all of them.**
`TaskBoxScope.scope` (`AzureDevOpsLoader.swift:120-135`) returns the *first*
target's org when targets > 1 — correct for one org's projects, a lie across
orgs. **Fix:** fill `scope` from the merged result: one account → today's wording;
several accounts → `"N orgs"`.

**6.3 🟡 The failure note can name an ambiguous project.**
`AzureProjectNote.compose` (`:138-162`) keys failures by project name. Two orgs
can each have a `ForesightManifold`. **Fix:** qualify the failure label as
`org/project` when more than one org is in play, plain `project` otherwise.

**6.4 Row order must stay total and stable.**
`PRFormatting.sorted` tiebreaks on `(provider, repo, number)`; add the org.
`TaskFormatting.sorted` tiebreaks on `id`; with two orgs' items potentially
sharing a numeric id the comparator can tie — the merge must interleave
deterministically (round-robin across accounts, the `AzureIDMerge.interleave`
idea), so the order does not reshuffle between ticks.

**6.5 Nothing may double-count.** Counts are unioned across accounts
(`totalCount` summed, `authoredCount`/`reviewingCount` summed, `capped`/`lowerBound`
OR-ed), never re-derived from the trimmed rows — the existing rule.

**6.6 🟡 Rows must be able to say which org they came from.**
`TaskItem` carries `project` but no org (`TaskBoxSnapshot.swift:26-59`), so with
two orgs that each have a `ForesightManifold`, every row and every failure note
is ambiguous. **Fix:** `TaskItem` gains a tolerant `organization: String?` too
(available as `target.organizationName`, `AzureDevOpsLoader.swift:393-436`). The
existing project toggle then renders `org/project` when more than one org is
bound, plain `project` otherwise — and the note (§6.3) uses the same
qualification. Additive and tolerant: `nil` for old rows, and GitHub rows never
have one.

## 7. Face and settings

**TaskBox face.** Unchanged at every size except the header's left word in the
multi-account case ("2 orgs") — "N orgs" is honest and short; naming them would
overflow. The lane legend, rows and checkmarks are computed from the merged task
list exactly as today. With more than one org bound, a row's project label renders
`org/project` (§6.6); the "Show project on rows" toggle still gates it.

**PRBox face.** Unchanged: the merged queue already spans two providers; three
Azure accounts are just more rows. Provider tag, draft mark, review glyph and row
links are untouched (each row's URL is built from its own org, §6.1).

**TaskBox / PRBox settings tabs.** The Azure `AccountPicker`
(`DeckApp.swift:1201-1252`) becomes a **multi-select** list for these two slots:
each Azure account is a row with a checkbox (label + `CredentialsCopy.subtitle`),
a caption ("N of 4 accounts bound", or the empty-state line), and the same
**Manage in Credentials…** link. A bound id that no longer resolves renders as a
checked **"Deleted account"** row (the single picker's existing device) so it can
be unbound. Selection is capped at 4: a fifth account is choosable but knocks out
one already bound — the cap bounds the request arithmetic (§5) and the list's
readability, exactly as the project cap's "how many slots fit" reasoning
(`CredentialAccount.swift:97-99`); nothing is lost from the keychain.
`nil`/single selection on the other three slots keeps today's `Picker`.

**TaskBox team picker.** The team row stays offered only when there is **exactly
one bound account with exactly one project** — with two accounts the total target
count is ≥ 2, the sprint chip hides, and a team picker would edit a setting that
does nothing (`AzureSprintRoute`, `AzureDevOpsLoader.swift:459-463`). The picker's
enablement must read the bound-account count, not just the project count.

**Credentials tab.** Unchanged per account. `slots(using:)` now reports a slot
when an account is *one of* its bound accounts, so "Used by" and the delete
confirmation stay truthful.

**Account page.** Unchanged — one org, up to eight project slots, **Load
projects**, Verify. Design C deliberately does not touch it.

## 8. Non-goals

- **The org-list-on-the-account design** (one account, several orgs) — blocked by
  §3; do not reintroduce without a different auth model.
- **Entra/AAD authentication** (the only way one token could span orgs) —
  `taskbox/prd.md:292`.
- **Multi-account for `openbox` / `shipbox` / `prboxGitHub`.** No recorded need;
  the picker stays single-select there.
- **Per-account row caps or per-account sprint chips.** One face, one cap, one
  sprint rule.
- **A second TaskBox provider** (Jira/Linear) — a separate follow-up.

## 9. Verification

- **`DeckSharedTests` (the whole live surface — this machine has one org):**
  `accountIDs` tolerant decode + encode-clears-legacy **+ a round-trip test for
  every other field in both structs** (the hand-written-`CodingKeys` trap, §4);
  `AzureAccountBinding` normalise/setSlot/cap; the multi-gate's four answers, the
  **mixed keychain-unavailable** case (§4), and the single-element regression
  against `CredentialGateTests`; `TaskBoxSnapshot` merge (counts summed,
  lowerBound OR-ed, rows interleaved, scope worded, notes joined, a failed *and*
  an unavailable account named); `PRRoleTotals` merge; `PRFormatting.deduped`
  **keeping two same-named repos with the same PR number from two orgs** and
  `sorted` with an org in the tiebreak; `TaskItem`/`PullRequestItem` tolerant
  decode of the new `organization` field and the `org/project` row label;
  `CredentialsCopy` subtitle/used-by; `CredentialsMigration` one-element
  assignment; the multi-picker's dangling-id row.
- **A regression test asserting `Set(ids).count == ids.count`** across two orgs
  with same-named projects and same PR numbers — the multi-project precedent.
- **`xcodebuild test -project native/Deck.xcodeproj -scheme DeckSharedTests
  -derivedDataPath native/build.noindex CODE_SIGNING_ALLOWED=NO`** stays green.
- **Recorded, not run:** the live two-org run (a second org + PAT). Added to
  `ROADMAP.md` as the follow-up, exactly as the team picker's caveat
  (`ROADMAP.md:975-977`). The Xcode build + `scripts/lsclean.sh` install check
  still runs.
- **CLAUDE.md grep checks stay clean**: nothing new read by the widget extension
  beyond `settings.json`; `grep -rn "\.enabled\|serverURL" native/DeckWidgets/`.

## 10. Acceptance

- One Azure account behaves byte-identically to today (gate, face, header,
  sprint, rows, notes) — the single-account regression is the bar.
- Two Azure accounts bound to TaskBox show both orgs' items in one interleaved,
  deterministic list, with the header reading "2 orgs".
- Two Azure accounts bound to PRBox keep both orgs' rows, **including** two
  same-named repos with the same PR number (no dropped row).
- Unbinding to one account, or to none, returns the face and the chip to today's
  behaviour; nothing is lost from the keychain.
- The account editor is unchanged and still verifies/loads per account.

## 11. Self-critique (2026-10-19)

Pressure-tested against the code and the CLAUDE.md invariants. Two red, eight
amber, each with a fix folded in above.

### 🔴 R1 — The one-way field migration is not implementable as first written

`TaskBoxSettings`/`PRAzureSettings` hand-write only `init(from:)`; `CodingKeys`
and `encode(to:)` are synthesized. Adding `accountIDs` beside `accountID` would
write both keys back, and dropping `accountID` would remove the key the legacy
decode needs. This is the recorded hand-written-`CodingKeys` trap.

**Fix (§4):** both structs get hand-written `CodingKeys` (both keys) and an
`encode(to:)` that omits `accountID`, plus a **round-trip test for every other
field** — a forgotten case compiles, decodes absent and never encodes.

### 🔴 R2 — A bound account whose keychain read failed would vanish silently

The first draft fetched "whatever resolved". If account B's keychain read failed
and account A answered, B disappeared with no word — the C1 mistake (telling the
user nothing when something they configured is not working).

**Fix (§4 rule 2):** the merge `note` names every bound account that did not
contribute, failed *or* `unavailable`; the slot chip is
`.credentialsUnavailable` only when **none** resolved.

### 🟡 A1 — The gate's blast radius

`CredentialGate.fetch(ResolvedCredential)` has ~26 consumers and test assertions
(`DeckAgent/main.swift:86-302`, `DeckApp.swift:515-611`, `AsyncSearchCoordinator`,
five test files). Changing it to carry a list is the widest part of this change.

**Fix (§4):** keep **one** rule table — `gate` returns the list form for every
slot and a `single` accessor serves the three single-slot callers — so there is
no second decision path to drift from, and the ~26 sites update mechanically
(single-element lists for the three single slots, so their tests are unchanged
in meaning).

### 🟡 A2 — "N orgs" loses which orgs, and same-named projects are ambiguous

Two orgs each with a `ForesightManifold` produce indistinguishable rows.

**Fix (§6.6):** `TaskItem`/`PullRequestItem` gain a tolerant `organization`;
rows and the failure note qualify as `org/project` when more than one org is
bound. The header stays "N orgs" (naming them would overflow).

### 🟡 A3 — A dangling bound account must be visible and unbindable

The single picker shows a "Deleted account" entry; the list form must too, or a
bound id that no longer resolves is invisible and cannot be cleared.

**Fix (§7):** a checked "Deleted account" row per dangling id.

### 🟡 A4 — The cap's rationale and overflow behaviour were unstated

Four is inherited from the interview, not derived here.

**Fix (§7):** state it bounds the request arithmetic and the list's readability
(the project cap's "how many slots fit" reasoning), and that a fifth account is
choosable by swapping one out — nothing is lost.

### 🟡 A5 — Search fan-out

The panel shares the loaders; `pr ` across 4 accounts × 8 projects is 64 queries
per debounce.

**Fix (§5):** bounded by the cap, paced by `RemoteSearchPolicy`, host-app-only,
and a 429 degrades only that section — the existing contract, restated.

### 🟡 A6 — Two widget-extension reads turn on the slot selection

`prBoxAzureIsOn` (and `prBoxGitHubIsOn`) are read *inside the extension*
(`CredentialsMigration.swift:145-148`) and must stay answerable from
`settings.json` without a token.

**Fix:** `prBoxAzureIsOn` becomes "any bound id resolves" (still non-secret), and
the CLAUDE.md `grep -rn "\.enabled\|serverURL" native/DeckWidgets/` check stays
clean; a test pins the list form.

### 🟡 A7 — The TaskBox team picker would edit a dead setting

It is offered per project count today; with two accounts the sprint chip hides,
so a live team picker would change nothing.

**Fix (§7):** gate it on exactly one bound account **and** one project.

### 🟡 A8 — Notes could grow unbounded across accounts

`AzureProjectNote.compose` is per account; naively joining every account's note
could produce a paragraph.

**Fix (§6.3):** compose per account with the org prefix when more than one org is
in play, then join with `" · "` — the MarketBox/ShipBox one-line precedent.

### 🟡 A9 — The merge must be one shared function, not two

The agent and the host app both write the snapshots; if each merged accounts its
own way they would drift.

**Fix:** the merges are **pure functions in `Shared/`** (`TaskBoxMerge`,
`PRRoleTotals.merged`) called by both, exactly as `PRSnapshotBuilder` is today —
the host and the agent stay line-for-line.

**Two red, eight amber, none silent.** The spec stands with the fixes folded into
§4, §5, §6, §7 and §9.


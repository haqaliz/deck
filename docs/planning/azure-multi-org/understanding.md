# Understanding — azure-multi-org

## What the work is really asking

Let **one** Azure DevOps `CredentialAccount` cover **more than one
organization**, so TaskBox and PRBox merge work items / pull requests from two
(or more) orgs into the one face they already build. Today an account is exactly
one organization carrying up to eight projects
(`native/Shared/CredentialAccount.swift:153-160`, `AzureAccountProjects`).

The natural shape is the one that shipped for projects, one level up: a list on
the account. But the earlier design was **declined**, so the PRD must pick a
mechanism rather than inherit one — see "The load-bearing design question".

## Current model (facts, all in `native/`)

| Piece | Where | Shape today |
|---|---|---|
| Account | `Shared/CredentialAccount.swift:143-236` | `organization: String` (one), `projects: [String]` (≤8), legacy `project: String` decoded once |
| Projects policy | `Shared/CredentialAccount.swift:96-141` | `AzureAccountProjects.normalise` / `.setSlot` / `.maxProjects = 8` |
| Slots | `Shared/CredentialAccount.swift:267-328` | `CredentialSlot.taskbox` / `.prboxAzure`; one account id each |
| Gate | `Shared/DeckSettings.swift:306-339` | `account(for:)` resolves a slot to one account, kind-checked |
| Targets | `Shared/AzureDevOpsLoader.swift:31-91` | `AzureTarget` = one org×project; `AzureTargets.normalise(organization:projects:)` = one org's projects |
| TaskBox fetch | `Shared/AzureDevOpsLoader.swift:479-565` | parallel WIQL per project → **one org-scoped `workitemsbatch`** (`targets[0].orgBase`, `:554`) → sprint only when 1 target |
| PRBox fetch | `Shared/AzureDevOpsLoader.swift:1001-1067` | identity from `targets[0].orgBase` (`connectionData`, org-scoped, `:1012`) → 2N project-scoped queries |
| Search (host-only) | `AzureDevOpsLoader.swift:580-608`, `:1124-…` | same one-org assumption |
| Settings UI | `DeckApp/DeckApp.swift:1601-1801` | one "Organization" `TextField` (`:1630`) + 8 project slots + **"Load projects"** (`:1754`, org-scoped `HostAzureProjectsLoader.list`) |
| Widget-tab picker | `DeckApp/DeckApp.swift:1201-1252` | `AccountPicker`, **single-select**, per kind |
| Copy | `Shared/CredentialsCopy.swift:45-146` | `azureScope` = `org / first +N`; `verifyHint` needs "an organization" |
| Verify | `Shared/CredentialVerification.swift:138-162` | org-level `connectionData`; project only satisfies `normalise` |

## Sites that must change, and why each is load-bearing

1. **Account model + decode** — a new org list with the single `organization`
   kept as a one-time legacy read (the exact pattern `projects`/`project` uses,
   `CredentialAccount.swift:199-207, 220-224`). A migration that moves a field
   must **clear the old copy** or the fallback keeps answering.
2. **Org-scoped calls become per-org.** `workitemsbatch` is *organization*-
   scoped and `connectionData` is *organization*-scoped. With N orgs there must
   be N batches and N identity calls — sending org B's ids to org A's batch
   endpoint is a silent wrong-answer, the `System.TeamProject` class of bug
   (`CLAUDE.md`, the Azure identity trap).
3. **PRBox row id must carry the org.** Today
   `azureDevOps:\(target.projectName)/\(repo)#\(number)` (`:949`) omits the org.
   With two orgs, two `api` repos and PR #12 collide — a duplicate `ForEach`
   key and one row silently dropped. This is the *same* bug multi-project fixed
   by adding the project.
4. **The face's scope name.** `TaskBoxScope.scope` (`:120-135`) returns the
   *first* target's org when there is more than one target — true for one org's
   projects, a lie across orgs. Same for the sprint chip/team picker (already
   gated to `targets.count == 1`, so that relaxes correctly on its own).
5. **Settings UI** — the org field becomes org slots (mirroring the project
   slots), and "Load projects" needs to know *which* org; the account-page
   subtitle/verify-hint copy follows.
6. **Copy + Verify** — `azureScope`/`missingForVerification` assume one org.

## 🔴 Blocker found while interviewing: a PAT is organization-scoped

**A single `CredentialAccount` (one token) cannot authenticate to two
organizations.** This makes the naive designs (A and B below, both "one account,
several orgs") infeasible on Deck's current auth model.

Evidence — Microsoft Learn, *Use personal access tokens*, updated 2026-09-21:

- *"Enter a name, **select one organization**, and set an expiration date."* — a
  PAT is created against exactly one org.
- *"If a tool doesn't support Microsoft Entra authentication, use an
  **organization-scoped** PAT…"*
- *"Azure DevOps is retiring global PATs. All existing global PATs stop working
  on **December 1, 2026**."* A **global** PAT was the only kind that worked
  across orgs (`allOrgs`), so it is the only thing that would make A/B work
  today — and Deck must not build on a credential type that dies in six weeks
  (today is 2026-10-19).
- *"When an account is disabled or removed from an organization, its PATs can no
  longer access **that organization's** resources."*
- The PAT Lifecycle create body carries `"allOrgs": false`.

This is presumably *why* the earlier interview concluded multi-org "needs a slot
that binds several accounts": one org ⇔ one PAT, so spanning orgs means spanning
credentials. `taskbox/prd.md:292` already fixes Deck as PAT-only ("No OAuth /
Entra ID"), so an Entra token (which *can* span orgs where the identity is a
member) is out of scope.

## The design question, restated under that constraint

- **A. Org list on the account** *(chosen at interview, then invalidated)* —
  infeasible: one token, one org.
- **B. Org→projects groups on the account** — same blocker.
- **C. The slot binds several accounts** — each Azure account stays exactly what
  it is (one org + its projects + its own PAT); TaskBox/PRBox point at **several**
  Azure accounts and merge. **The only design compatible with org-scoped PATs.**
  Cost: the picker becomes multi-select; `accountID(for:)` → `accountIDs(for:)`;
  `gate`, `slots(using:)`, "Used by" copy and the loaders' entry points all
  widen; the snapshot merge (scope name, sprint, lane counts, row order) moves
  up a level.
- **D. Multi-org inside one account, with a token per org** — the account page
  grows an org list each carrying its own token (one keychain item per org).
  Keeps the one-account mental model but breaks "an account has one
  credential/one keychain item" and needs a new keychain item shape.

Recommendation: **C**, scoped to the two Azure slots (`.taskbox`,
`.prboxAzure`); it is the model the credential system already implements, and
the loader generalisation is "iterate accounts" — the same shape PRBox already
uses to merge two providers.

## Ambiguities and risks

- **Unverifiable live here.** This org has one organization, so every claim is
  unit-test-only; the live two-org run is a recorded follow-up (the team
  picker's precedent, `ROADMAP.md:975-977`). Plan the verification as
  `DeckSharedTests`, not a live probe.
- **Request budget grows.** N orgs × M projects: TaskBox is N×M WIQL + N
  batches; PRBox is N identity + 2×N×M queries, all in the existing
  `withThrowingTaskGroup`. Nothing above 5 projects has been measured
  (`azure-project-cap/prd.md`), let alone above one org. State the arithmetic,
  do not claim a measurement.
- **Partial failure must stay per-project** and now per-org: some orgs an answer,
  none a thrown tick, last good snapshot stands (`AzureProjectNote`).
- **Fetch chips stay one per slot** (`.taskbox`, `.prboxAzure`) — multi-project
  already settled that; multi-org must not multiply it.

## Shell invariants (CLAUDE.md)

- Settings live in the app only; the widget extension must keep reading only
  answerable-from-`settings.json` non-secret fields. `grep -rn "\.enabled\|serverURL"
  native/DeckWidgets/` must stay clean — add an org-list grep for any new field a
  widget might reach for.
- `DeckSettings`/`CredentialAccount` decoders stay tolerant (`decodeIfPresent`);
  one section failing must not reset the file.
- Keys are stable on disk (`CredentialKind` raw values; `CredentialAccount`
  `CodingKeys` is hand-written — a forgotten case compiles and silently drops).
- No Swift Charts, no `ENABLE_HARDENED_RUNTIME` drift, version bump only if the
  widget descriptor set changes (it should not — faces are unchanged).

## Build / test facts

- xcodegen + xcodebuild, not SwiftPM. A new `.swift` file needs
  `xcodegen generate --spec native/project.yml` or it is silently not compiled.
- Tests: `xcodebuild test -project native/Deck.xcodeproj -scheme DeckSharedTests
  -derivedDataPath native/build.noindex CODE_SIGNING_ALLOWED=NO` (current suite
  ~1665 tests, `credentials-legacy-fallback`, 2026-10-12).
- Build only into `native/build.noindex`; `scripts/lsclean.sh` after a release
  build.
- Test files likely to extend: `AzureAccountProjectsTests`, `AzureMultiProjectTests`,
  `CredentialGateTests`, `CredentialVerificationTests`, `CredentialsCopyTests`,
  `DecodeTests`, `CredentialsMigrationTests`.

## Open questions for the PRD interview

1. Which design — **A** (org list, cross product), **B** (org→projects groups),
   or revive **C**? This decides everything else.
2. Cap: how many orgs (mirror the 8-project reasoning, or smaller — it is a
   multiplier on the same slot UI)?
3. Does multi-org change the **sprint chip / team picker** rules at all, or do
   they simply stay gated to a single target?
4. Scope of "done" given one org on this machine: unit tests only, with the live
   two-org check recorded — agreed?
5. Settings UI for orgs: org slots like projects, or a grid/table of
   org×projects if B?

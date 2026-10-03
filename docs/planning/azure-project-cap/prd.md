# PRD — azure-project-cap

Status: draft for review (2026-10-03). Slug confirmed: `azure-project-cap`.
Inputs: `docs/planning/_card/issue.md`, `understanding.md`.

## 1. The ask, in one sentence

Raise the per-account Azure DevOps project limit from 5 to **8** so one account
covers a six-project organization (and leaves headroom), for TaskBox and PRBox.

## 2. Decisions taken (interview, 2026-10-03)

| Question | Decision | Why |
|---|---|---|
| Ceiling | **8** | Fits the live org (6) with two spare; still a form that fits one screen. |
| Slots vs list | **Keep numbered slots, bump the constant** | The original cap was a slot-count UI choice (`CredentialAccount.swift:97-99`, `probe.md` F3). A list is a larger UI change this follow-up does not need. |
| Live probe | **Not run** | Cost is not the constraint; the design does not depend on it. See §6 for what is therefore unmeasured. |

## 3. User-visible spec

There is no widget face change. TaskBox and PRBox render exactly as today; they
simply receive rows from more projects when an account lists more.

**Settings, Credentials tab, Azure account page** (`DeckApp.swift:1553`):
- The project list shows **8** slots instead of 5. Slot 1 is "Project"; slots
  2-8 are "Project N (optional)". Picker vs text-field behaviour is unchanged.
- The sentence at `DeckApp.swift:2335` ("up to five projects") becomes "up to
  eight projects".
- Defaults unchanged: new accounts have no projects.

**Existing data:** an account with 1-5 projects decodes and behaves identically.
Slots 6-8 appear empty. No migration, no schema change, no new settings key.

## 4. Data path and cost

Unchanged mechanism, larger N. All of it already routes through
`AzureAccountProjects.normalise`, which is the single place the cap is applied.

| Surface | Requests per tick at N projects | At N=5 | At N=8 |
|---|---|---|---|
| TaskBox | N WIQL + 1 batch (`ROADMAP.md:412-419`) | 6 | 9 |
| PRBox (Azure half) | 1 identity + 2N PR queries | 11 | 17 |
| Settings **Test** (custom WIQL) | N WIQL, one per project, on click | 5 | 8 |

- The batch's 200-id ceiling is global (`AzureIDMerge.interleave`), so more
  projects thin each project's share of rows rather than growing the request.
- PRBox's 2N queries run in an unbounded `withThrowingTaskGroup`. At 17 that is
  an acceptable burst against one host, by analogy with ShipBox's concurrent
  fan-out (~5 requests, 2.1s) and the multi-project work at N<=5. **Nothing
  here has been measured at N>5, and Azure's throttling behaviour for this
  burst is unknown** — an assumption, not a finding. See §6.
- Failure behaviour is unchanged: some projects failing is a note naming them,
  none failing throws and the last good snapshot stands.

## 5. Shell fit

- Reuses the existing account editor, `normalise`, loaders and merge. No new
  file, no new widget, no snapshot or settings schema change.
- CLAUDE.md invariants: no Swift Charts, no widget-extension read of project
  count (the extension-side-reads trap is not triggered), no new widget so no
  version bump is required *by this feature*. A release bump is separate.
- **Downgrade is lossy:** an older Deck `normalise`s a 6-8 project list to 5 on
  decode and rewrites it. Accepted; users who downgrade lose slots 6-8 only.

## 6. Non-goals

- Not an add/remove list UI (recorded alternative: MarketBox ticker list).
- Not multi-org, per-widget project subsets, or WIQL presets (separate
  follow-ups in `ROADMAP.md`).
- Not bounding PRBox's fan-out width.
- No live measurement of request count, wall-clock or snapshot size at N=6/8.
  Those stay **unmeasured**; the ROADMAP entry must say so rather than imply a
  probe was done.

## 7. Change list

Behaviour: `CredentialAccount.swift:100` `maxProjects = 8`; rewrite the doc
comment at :97-99 (it argues "five, matching ShipBox"), plus :102 and :152.

Copy that refers to *this* cap (found by reading each hit, not by grep alone):
- User-visible: `DeckApp.swift:2335`; `README.md:60`, `:62`, `:219`, `:220`
  ("five slots"), `:227` ("The same five slots serve PRBox").
- Comments: `DeckApp.swift:1544`, `:1599`; `CredentialVerification.swift:24`,
  `:141` ("all five projects ... cost five more calls" — rewrite to be
  count-free); `AzureDevOpsLoader.swift:657`; `CredentialsMigration.swift:14`;
  `AzureAccountProjectsTests.swift:139`, `:157` (comment/section titles).
- **Deliberately left alone** (the word "five" is about something else):
  ShipBox's five repos (`README.md:59`, `:165`, `:169`; `DeckApp.swift:2174`;
  `DeckSettings.swift:749`), the five keychain credentials, MarketBox rows.

Tests (`AzureAccountProjectsTests.swift`): `testCapsAtFive` becomes a cap-at-8
test; `setSlot` past-the-cap case moves from slot 5 to slot 8
(`:157-189`, using an 8-element fixture); add a regression that a 6-project
list survives `normalise` and a decode round-trip (the live org's shape).

Docs: ROADMAP M8 entry ticked (and its "five" mentions in the multi-project
entry annotated, not rewritten); `azure-multi-project/*` left as history.

## 8. Acceptance

- `DeckSharedTests` green with the updated and new tests.
- A 6-project account round-trips through decode/encode/normalise intact; 9+
  names truncate to the first 8 in order.
- The built app's account page shows 8 slots (visual check on a build, not a
  claim from tests).
- Every site in the §7 "refers to this cap" list reads correctly; the "left
  alone" list is untouched. (A blanket `grep five` is not the check — it also
  hits ShipBox, keychain and MarketBox wording that is correct.)

## 9. Open questions

None blocking. Decide at review only if you want a different ceiling than 8.

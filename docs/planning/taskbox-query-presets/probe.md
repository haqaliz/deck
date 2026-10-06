# Probe — TaskBox team context against a live org (2026-10-07)

Org `ForesightAnalytics`, project `ForesightManifold`, the TaskBox account's PAT
(read from the keychain, never printed). `$top=201`, the production query shape:
`SELECT [System.Id] FROM WorkItems WHERE [System.TeamProject] = @project AND (…) ORDER BY [System.ChangedDate] DESC`.

## Teams listing

| # | Call | Result |
|---|---|---|
| F1 | `GET {org}/_apis/projects/ForesightManifold/teams?api-version=7.1` | 200, **one team**: `ForesightManifold Team` |
| F2 | same for `ForesightDevops` | 200, one team: `ForesightDevops Team` |
| F3 | team object fields | `name`, `id`, `projectId`, `projectName`, `description`, `identityUrl`, `url` |

The existing PAT lists teams; no extra scope was needed.

## `@CurrentIteration` with and without a team

| # | Condition | Result |
|---|---|---|
| P16 | `[System.IterationPath] = @CurrentIteration` (no team) | 200, 30 ids |
| P17 | `[System.IterationPath] = @CurrentIteration('[ForesightManifold]\ForesightManifold Team')` | 200, 30 ids — **same as P16** (one team per project) |
| P18 | bogus team name in the literal | **500**, `VS402612: The macro '@CurrentIteration' is not supported without a team context.` |
| P19 | brackets omitted (`'ForesightManifold\… Team'`) | **500**, `'…' is not of the form '[project]\team'` |
| P20 | literal for **another** project (`'[ForesightDevops]\ForesightDevops Team'`) run against `ForesightManifold` | **200, 0 ids** — silent |
| P21 | team name containing a space | 200, 30 ids — no escaping problem |

## Sprint chip route

| # | Call | Result |
|---|---|---|
| F4 | `{org}/{project}/_apis/work/teamsettings/iterations?$timeframe=current` (today's call) | 200, `Sprint 63` |
| F5 | `{org}/{project}/{team}/_apis/work/teamsettings/iterations?$timeframe=current` | 200, `Sprint 63` — same here, because there is one team |

## What this settles

1. **The literal takes the team's name, not its id, and brackets are required**
   (P19 is a 500 with a readable message).
2. **A team literal only answers for its own project.** Run against a different
   project it is **200 with 0 ids** (P20) — the same silently-empty shape as a
   misspelt state value (the earlier probe's P4). So one team literal cannot
   serve a multi-project account honestly: every other project silently reports
   "no matches".
3. **A wrong macro is a 500, not a 400.** `WiqlResponse.interpret` turns only
   400 into `queryRejected`; P18/P19 would today render as "unexpected
   response". The PRD must decide how (and how narrowly) to read a 500 message.
4. **This org has one team per project**, so the team segment changes nothing
   today (P16 = P17, F4 = F5). The picker is for orgs where the working team is
   not the project's default; that is worth saying honestly in the PRD.
5. **A team route exists for the chip** (F5), with the same one-project
   constraint the chip already has (`fetch` shows it only for a single project).

Note: P7 in `../taskbox-custom-wiql/probe.md` measured 70 ids on 2026-09-25;
today's no-team query is 30 — item counts move with sprints and state, so rely
on the shape of the answers, not the numbers.

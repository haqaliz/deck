# Brief — Azure DevOps multi-project for TaskBox and PRBox

Source: `deck-next` pick (2026-08-28). No GitHub issue; inline brief.

TaskBox and PRBox each show Azure DevOps work from exactly one project; both
list "multi-project/multi-org" as an open follow-up (ROADMAP.md:165, :193), and
TaskBox's own live probe measured 67 items across three projects against the 25
in the configured one (ROADMAP.md:151) — so most of this org's work is invisible
today.

Resolve the model fork first: `CredentialAccount.project` is a single String
(native/Shared/CredentialAccount.swift:104) and a `CredentialSlot` binds one
account, so decide between a project list on the account and multiple accounts
per slot (the latter makes the user paste the same PAT twice, since keychain
items are keyed per account id) before writing the PRD.

Mind the per-tick cost: TaskBox is WIQL + workitemsbatch + team iterations per
project and PRBox is one call per project per criterion, against a measured
9.4s-serial / 2.1s-concurrent fan-out and a 60s agent cadence — cap the project
count and follow `HostGitHubLoader.inParallel`.

Keep the WIQL `[System.TeamProject]` clause per project (a project-scoped URL
does not filter) and keep PRBox's `connectionData` identity resolution, which
must fail rather than fall back.

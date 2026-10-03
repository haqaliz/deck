# Card: azure-project-cap (feat)

Inline brief (from `deck-next`, 2026-10-03; no GitHub issue).

Raise `AzureAccountProjects.maxProjects` (`native/Shared/CredentialAccount.swift:100`,
currently 5) so one Azure account covers the user's six-project org, for both
TaskBox and PRBox. The account editor's slot list already iterates `maxProjects`
(`DeckApp.swift:1553`), so confirm it grows cleanly and that migration and
normalisation (`CredentialsMigration`, `CredentialAccount.swift:113-134`) still hold.

Probe live first: measure request count, wall-clock and snapshot size at N=6 and
at the candidate ceiling, since PRBox costs 2N+1 calls per 60s tick against a 10s
request timeout, then choose the cap from the numbers.

Caveat: this is a cost-vs-ceiling decision, not just a constant. Update the
pinned test (`AzureAccountProjectsTests.swift:40`), and tick ROADMAP M8 plus README.

Source: ROADMAP.md M8 "Azure: raise the five-project cap" (line 892); multi-project
entry open follow-up (ROADMAP.md:433-436).

# TaskBox — inline brief

Source: `ROADMAP.md` M5 widget slate (no GitHub issue). Verbatim:

> - [ ] **TaskBox** — tasks: due/overdue counts + the next few items.
>       First provider is **Azure DevOps** (work items assigned to me, via WIQL
>       `[System.AssignedTo] = @Me` + the workitems batch endpoint, PAT over
>       Basic auth — the same static-token shape as ShipBox, no OAuth).
>       Dev machine already targets org `Manifold`, project `Manifold`.
>       Design the snapshot around a **provider-agnostic `TaskItem`** (id,
>       title, state, url, provider) so GitHub Issues / Jira / Linear /
>       Reminders drop in later without reshaping the store. Only the Azure
>       DevOps provider ships in slice 1.

Type: `feat` · Slug: `taskbox` · Branch: `feat/taskbox/aliz`

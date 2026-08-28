# Probe — `_apis/projects` (2026-08-28)

`GET https://dev.azure.com/{org}/_apis/projects?api-version=7.1&$top=200`,
Basic auth with the PAT already stored for the `ForesightAnalytics` account.

**Status 200, 1657 bytes, `count: 6`.**

```
{ "count": 6, "value": [ { id, name, url, state, revision, visibility,
                           lastUpdateTime }, … ] }
```

## The three questions the plan asked

1. **Does the existing PAT get a 200 here?** Yes. Discovery is the primary
   path, and the free-text fallback drops to a genuine corner case (a PAT
   scoped tighter than this one). Keep the fallback — it costs one `else`
   branch — but the pickers can be the default presentation.
2. **Is the display name at `value[].name`?** Yes, and it is the cased display
   name, not a slug.
3. **How many projects does the org have?** **Six** — see the cap note below.

## What the probe changed

**F1 — the PRD's live-verification target does not exist.** The brief and PRD
name the two projects as `ForesightManifold` + `Manifold`. There is no project
called `Manifold` in this org; the neighbour is **`Manifold Ops`**. Phase 10
targets `ForesightManifold` + `Manifold Ops`.

**F2 — a real project name contains a space.** `Manifold Ops` exercises
`AzureTarget.normalise`'s percent-encoding on the live path, not just in
theory. Every phase-4/5 test that builds a URL uses a spaced name, and phase 10
checks the deep links for that project specifically. A project name is also
free to contain other URL-hostile characters; the existing
`.urlPathAllowed` encoding already covers them.

**F3 — the org has six projects against a cap of five.** The cap was chosen in
the interview (ShipBox's five-repo precedent) before the count was known.
Cost is not the constraint — six projects is 6 WIQL + 1 batch — so the cap is a
UI decision about slot count, not a budget. Left at five; raising it is a
one-constant change if a user ever wants all six.

**F4 — two fields worth using.** `state` is `wellFormed` for all six, so
discovery filters to `wellFormed` and a project mid-creation or mid-deletion
never reaches a picker. `lastUpdateTime` is present but **not** used for
ordering: the picker sorts by name, because a list that reshuffles between
openings is the MarketBox lesson.

No GUIDs, URLs or revision numbers are recorded here — the parser needs none of
them.

# Card — hardened-runtime pre-flight

**Type:** feat · **Branch:** `feat/hardened-runtime-preflight/aliz` · **Source:** inline brief (`deck-next`, 2026-09-06)

Turn on `ENABLE_HARDENED_RUNTIME` for all three shipping targets (DeckApp,
DeckWidgets, DeckAgent — not DeckSharedTests) while still signing with the
existing "Apple Development" identity, so the notarization release is a
certificate swap rather than a debugging session on a release that also resets
every user's TCC grant and cannot be rolled back symmetrically.

`native/project.yml` currently has `ENABLE_HARDENED_RUNTIME: NO` at :51 and :88
and the key is missing entirely from the DeckAgent target at :123 — a missed
target is one of the two typical causes of an `Invalid` notarization per
`docs/planning/notarization/runbook.md` Step 2.

Verify against the installed copy in `/Applications`, not `build.noindex`:

- the extension registers (`pluginkit`), all fourteen widgets re-add from the
  gallery and render at all three sizes;
- both agents write (`processes.json` and `agent-heartbeat.json` mtimes advance);
- DeckAgent's subprocesses still run (`ps`, `docker`, `git`);
- BatBox's `@_silgen_name` `IOPSCopyPowerSourcesByType` accessory section still
  populates **inside the sandboxed extension** — check it against
  `pmset -g accps` rather than the unified log, which can be empty on this
  machine.

If AMFI objects, `log stream --predicate 'sender == "AMFI"'` names the
restriction.

While in project.yml/CI, also:

- drop `-allowProvisioningDeviceRegistration` from the release build line;
- fix the stale `--no-quarantine` claim in ROADMAP.md's Homebrew entry (the flag
  no longer exists; README.md:92 is already correct).

Record the result in `docs/planning/hardened-runtime-preflight/` and cross-link
it from the notarization runbook so the paid day starts with Step 1.

## Why this, now (from `deck-next`)

- M3 and M5 are both marked *candidate list exhausted*; the three remaining
  widget ideas carry recorded blockers (MediaRemote entitlement, SMC private
  API, Mail Envelope Index). Everything unchecked lives in M7 — launch readiness.
- Notarization is the highest-value M7 item (it removes the Gatekeeper dance
  that currently *deletes* `/Applications/Deck.app` on a quarantined launch, and
  the 2027-08-09 expiry cliff), but it is gated on a $99 purchase and an
  individual-vs-organization decision. This is the part of it that needs neither.

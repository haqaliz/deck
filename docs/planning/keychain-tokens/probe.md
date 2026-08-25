# Live probe — can DeckAgent read a keychain item Deck.app wrote?

Run 2026-08-25, on the dev machine, before the PRD. Two signed stand-ins were
built and signed with the real identity (`Apple Development: haqaliz@aol.com`,
OU = team **K6X49DG8VF**, the team in `native/project.yml`):

| Stand-in | Shape | Models |
|---|---|---|
| `SpikeWriter.app` | `.app` bundle, id `com.deck.spike.writer` | `Deck.app` (writes from the settings tabs) |
| `SpikeReader` | bare Mach-O, no bundle, signing identifier = filename | `DeckAgent` (`type: tool`, reads under launchd) |

Every read used `kSecUseAuthenticationUI: kSecUseAuthenticationUIFail`, so a
read that *would* have shown a dialog fails instead of blocking. That is the
whole point: it makes "would prompt" observable rather than a hang.

## Result 1 — the card's blocking risk does not materialize

The card required proof of an agent-side read **under launchd, not from a
terminal**. Ran as a real LaunchAgent (`launchctl bootstrap gui/$(id -u)`):

```
READER mode=legacy ctx=launchd status=0 (No error.) value=SECRET-VALUE-legacy
```

A generic-password item added by the bundled writer is readable by the bare
tool, in a launchd job, **with no prompt and with UI suppressed**. The feared
`errSecInteractionNotAllowed` never appeared. The per-binary ACL that the card
worried about is not applied by `SecItemAdd`'s defaults.

## Result 2 — the access-group route is not merely hard, it is fatal

The presumed fix (a shared `keychain-access-groups` entitlement) cannot be used
under Deck's current signing. Two measurements:

- **Data protection keychain without the entitlement**: writing fails outright.
  `SecItemAdd` with `kSecUseDataProtectionKeychain: true` returns
  **`-34018` (errSecMissingEntitlement)**. So the entitlement is mandatory for
  that keychain, not optional.
- **With the entitlement**: the process is **SIGKILLed at launch** — exit 137,
  before `main` — for *both* the `.app` and the bare tool. A control run
  isolates the cause exactly: same binary, entitlements stripped → exit 0;
  entitlements re-added → exit 137; stripped again → exit 0.

`keychain-access-groups` needs a provisioning profile to authorise it. An
`.app` can embed one (`Contents/embedded.provisionprofile`); **`DeckAgent` is a
`type: tool` with no bundle and has nowhere to put one**. This route is closed
until the signing story changes, and possibly after.

## Result 3 — the keychain buys confidentiality at rest, not process isolation

This is the finding that should shape how the feature is described. Three
different binaries read the value with **no prompt**:

| Reader | Signature | Result |
|---|---|---|
| `SpikeReader` | the team identity | `status=0`, value returned |
| ad-hoc copy | `codesign -s -`, a different identity entirely | `status=0`, value returned |
| `/usr/bin/security` | Apple's own, in no trusted list | value printed |

An explicit restrictive ACL did not change this. A second item was written with
`SecAccessCreate` trusting **only** two named binaries
(`SecTrustedApplicationCreateFromPath`); `SecItemAdd` accepted it
(`add=0`), and the untrusted ad-hoc copy and `/usr/bin/security` **still read
it without a prompt**.

*Measured, not explained.* The likeliest reading is that `SecItemAdd` does not
apply `kSecAttrAccess` the way the legacy `SecKeychainItemCreateFromContent`
API did, so the item was created with default access regardless. Either way,
the observable behaviour on this machine is that any process running as the
user reads the value.

**Therefore:** moving the five tokens into the keychain takes them out of a
plaintext file that gets copied, backed up, synced and sanitised — it does
**not** stop a local process from reading them. Any wording that claims
otherwise, in the README or the settings UI, would be false.

## Not tested — a locked login keychain

`DeckAgent` runs every 60s from login. If the login keychain is locked (the
login window, or a keychain password that differs from the account password),
reads should fail with `errSecInteractionNotAllowed` and four widgets would
lose their credentials at once. **This was deliberately not tested**:
`security lock-keychain` on the user's own machine would leave them with
unlock prompts across their other apps, and it cannot be undone without their
password. The design must assume it can happen and classify it as its own
fetch outcome (see the PRD) rather than as "not configured".

## Cleanup

The LaunchAgent was booted out and its plist removed; both probe keychain items
were deleted (`security find-generic-password -s com.deck.spike` finds nothing).
Spike sources live in the session scratchpad, not in the repo.

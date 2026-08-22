# Notarization runbook — what to do the day the $99 program is bought

Everything Deck needs to become a normally installable Mac app, in order, with
the verification gate for each step. Nothing here is possible without the paid
[Apple Developer Program](https://developer.apple.com/programs/) ($99/yr).

Status as of v1.20: Deck is signed with an **Apple Development** certificate and
is **not notarized**. It runs on any Mac once the quarantine flag is cleared by
hand (`xattr -dr com.apple.quarantine`), which is what `--no-quarantine` does in
the Homebrew cask. There is no device restriction — the bundle carries no
provisioning profile, and its only entitlement is `app-sandbox` on the
extension. Gatekeeper is the sole obstacle.

## Why this is worth $99

Two things, and the second matters more than people expect.

1. **Gatekeeper stops refusing the app.** No `xattr`, no `--no-quarantine`, no
   trip through System Settings → Privacy & Security. On macOS 15 the old
   Control-click → Open shortcut is gone, so today's workaround is a Terminal
   command, and that is where most first-time users give up.

2. **The signature stops expiring.** Xcode signs development builds with *no
   secure timestamp*:

   ```
   Signed Time=Aug 23, 2026            ← the local clock, meaningless to Gatekeeper
   notAfter=Aug  9 21:57:13 2027 GMT   ← the certificate
   ```

   Signature validity is therefore tied to the certificate's lifetime. On
   **2027-08-09** the certificate expires and every copy of Deck in the world
   stops launching — not a warning, the signature no longer validates. Renewing
   produces a *different* identity, so it is a forced re-download for everyone.
   A Developer ID signature carries a real `Timestamp=` from Apple's timestamp
   authority and keeps working after the certificate expires.

## Step 0 — Decide individual or organization (do this first, it is hard to undo)

Gatekeeper shows the team name in its dialogs, and it is baked into the
certificate.

| | Individual | Organization |
|---|---|---|
| Name users see | `Ali Haqiqi` | the company name |
| Requires | an Apple ID | a legal entity + a free [D-U-N-S number](https://developer.apple.com/support/D-U-N-S/) |
| Time to enrol | hours to ~2 days | ~1–2 weeks (D-U-N-S lookup, then a verification call) |
| Cost | $99/yr | $99/yr |

Converting individual → organization later issues a **new team ID**, which means
a new signing identity, which resets every user's TCC grant and breaks
auto-update continuity — the same class of pain as changing the bundle
identifier. Decide once, here.

If the launch is under a personal name anyway, individual is fine and much
faster.

## Step 1 — Create the Developer ID Application certificate

Xcode → Settings → Accounts → select the team → **Manage Certificates…** → **+**
→ **Developer ID Application**. (Or the
[certificates page](https://developer.apple.com/account/resources/certificates).)

Deck does **not** need a Developer ID *Installer* certificate — that is for
`.pkg` installers, and Deck ships a `.dmg`.

Apple caps Developer ID Application certificates per account (5 at the time of
writing) and they cannot be deleted freely, so do not create throwaways.

Export it for CI, private key included:

```bash
# Keychain Access → login → Certificates → right-click the
# "Developer ID Application: …" entry → Export → .p12 → set a strong password.
base64 -i DeveloperID.p12 | pbcopy
```

Update the GitHub repository secrets:

| Secret | New value |
|---|---|
| `APPLE_CERT_P12_BASE64` | the base64 above (replaces the Apple Development export) |
| `APPLE_CERT_PASSWORD` | the .p12 password |
| `APPLE_ID`, `APPLE_APP_SPECIFIC_PASSWORD`, `APPLE_TEAM_ID` | unchanged — `notarytool` reuses them |

The app-specific password comes from appleid.apple.com → Sign-In & Security. An
App Store Connect API key is the tidier long-term option for CI (no coupling to
one person's 2FA), but the three secrets already configured are enough to start.

**Gate:** `security find-identity -v -p codesigning` lists
`Developer ID Application: … (TEAMID)`.

## Step 2 — Switch the project to Developer ID + hardened runtime

In `native/project.yml`, for **all three shipping targets** (`DeckApp`,
`DeckWidgets`, `DeckAgent` — not `DeckSharedTests`):

```yaml
        CODE_SIGN_IDENTITY: "Developer ID Application"   # was "Apple Development"
        ENABLE_HARDENED_RUNTIME: YES                     # was NO — required to notarize
```

Keep `CODE_SIGN_INJECT_BASE_ENTITLEMENTS: NO` under `configs: Release:`.
Developer ID signing drops `get-task-allow` by itself, but leaving the line
explicit means a future switch back to development signing cannot silently
reintroduce a debuggable release.

No provisioning profile is needed. Profiles are only required for entitlements
Apple gates (iCloud, push, app groups); plain `com.apple.security.app-sandbox`
on the extension is not one of them.

In `.github/workflows/deck.yml`, drop the development-only build flags:

```diff
-            -derivedDataPath native/build.noindex -allowProvisioningUpdates \
-            -allowProvisioningDeviceRegistration build
+            -derivedDataPath native/build.noindex build
```

Then `xcodegen generate --spec native/project.yml`.

**Gate:** after a local Release build,

```bash
codesign -dvvv native/build.noindex/Build/Products/Release/Deck.app 2>&1 \
  | grep -E "Authority=Developer ID|flags=.*runtime"
```

shows the Developer ID authority **and** the `runtime` flag.

### Hardened runtime: what to watch

Nothing Deck does should need an exception, but confirm rather than assume:

- **DeckAgent spawns subprocesses** (`ps`, `docker`, `git`). Hardened runtime
  does not restrict spawning children, so no entitlement is required.
- **BatBox binds `IOPSCopyPowerSourcesByType` with `@_silgen_name`.** Private
  API is rejected by *App Store review*, not by *notarization*, so Developer ID
  distribution is fine. It still must be re-verified inside the sandboxed
  extension after the identity change (Step 5).
- Deck uses no JIT, no `DYLD_INSERT_LIBRARIES`, no unsigned executable memory,
  so none of the corresponding exception entitlements apply.

If a hardened-runtime crash does appear, `log stream --predicate 'sender ==
"AMFI"'` names the restriction it hit.

## Step 3 — Notarize and staple in CI

Two passes: the `.app` gets its own ticket so it launches offline once copied
out of the image, then the `.dmg` gets one so the image itself opens cleanly.
Stapling only the DMG leaves the installed app relying on an online Gatekeeper
check.

Insert between the build and packaging steps in `.github/workflows/deck.yml`:

```bash
cd native/build.noindex/Build/Products/Release

# ditto, not zip: zip mangles symlinks and nested code signatures, and
# notarization rejects the result with a confusing error.
ditto -c -k --keepParent Deck.app Deck-app.zip

xcrun notarytool submit Deck-app.zip \
  --apple-id "$APPLE_ID" --password "$APPLE_APP_SPECIFIC_PASSWORD" \
  --team-id "$APPLE_TEAM_ID" --wait
xcrun stapler staple Deck.app
rm Deck-app.zip
```

The existing DMG step then builds from the **stapled** app, and a second pass
notarizes the image itself:

```bash
xcrun notarytool submit "Deck-${VERSION}.dmg" \
  --apple-id "$APPLE_ID" --password "$APPLE_APP_SPECIFIC_PASSWORD" \
  --team-id "$APPLE_TEAM_ID" --wait
xcrun stapler staple "Deck-${VERSION}.dmg"
```

Order matters: **staple before `shasum`**, or the published checksum will not
match the bytes users download.

When a submission comes back `Invalid`, the reason is never in the summary:

```bash
xcrun notarytool log <submission-id> \
  --apple-id "$APPLE_ID" --password "$APPLE_APP_SPECIFIC_PASSWORD" \
  --team-id "$APPLE_TEAM_ID"
```

Typical first-run causes are a target that missed `ENABLE_HARDENED_RUNTIME`, or
a nested binary (`DeckAgent`, `DeckWidgets.appex`) signed with the old identity.

Notarization normally returns in minutes, but Apple gives no SLA — allow for a
slow run before assuming the workflow hung.

## Step 4 — Verification gates

Download the published DMG on a machine that has never built Deck, then:

```bash
spctl -a -vvv -t exec /Applications/Deck.app
#   → accepted   source=Notarized Developer ID     (today: "rejected")

codesign -dvvv /Applications/Deck.app 2>&1 | grep -E "Timestamp|Signed Time"
#   → Timestamp=...    and NOT "Signed Time=..."   ← this is the expiry fix

xcrun stapler validate /Applications/Deck.app
xcrun stapler validate Deck-vX.Y.dmg
#   → The validate action worked!

codesign -d --entitlements - /Applications/Deck.app 2>&1 | grep -c get-task-allow
#   → 0
```

Then the functional pass, on a **second Mac outside the signing team** — the one
assumption never yet tested:

- [ ] The DMG opens with no Gatekeeper prompt at all, and the app launches
- [ ] `pluginkit -m -i com.deck.app.widgets` registers the extension
- [ ] All twelve widgets appear in the Widget Center gallery
- [ ] Each renders at small, medium and large

## Step 5 — Re-test what the identity change resets

TCC grants are keyed to the code signature's designated requirement, so
switching from Apple Development to Developer ID invalidates every existing
grant. Users are re-prompted once; that is expected, but it must be confirmed to
still *work*:

- [ ] Calendar access prompt appears for **Deck** and again for **DeckAgent**
      (separately signed), and CalBox fills in afterwards
- [ ] "Access data from other apps" prompt appears, and LiveBox's process list
      fills in afterwards
- [ ] BatBox accessory batteries still resolve inside the sandboxed extension —
      the `IOPSCopyPowerSourcesByType(4)` SPI. Ground truth: `pmset -g accps`
- [ ] The LaunchAgents install and both snapshots pump on the 60s cadence

## Step 6 — Ride the same release with the other install-invalidating changes

The Developer ID switch already forces every user to re-grant permissions, so
anything else with the same cost should ship in the same version rather than
inflicting a second round:

- [ ] **Bundle identifier rename.** `com.deck.app` / `com.deck.agent` is
      reverse-DNS for a domain nobody owns. Changing it later forces users to
      re-add every widget and re-grant TCC. Needs a decision on the new
      identifier.
- [ ] **Keychain for the three tokens** (GitHub, Azure DevOps PAT, OpenBox).
      The app and agent are unsandboxed and the widget never needs them.
      `settings.json` at 0600 is the interim measure.
- [ ] **`SMAppService`** instead of hand-written LaunchAgent plists — it puts
      Deck in System Settings → Login Items, where a cautious user looks first.

## Step 7 — Drop the quarantine workaround everywhere

Once a notarized release is out, these all become wrong and read as amateurish:

- [ ] `homebrew/deck.rb` — remove `--no-quarantine` from the header comment and
      the `caveats` block, and mirror the file to the tap
- [ ] `README.md` — the `xattr` command, the "Why the extra command?" callout,
      and `--no-quarantine` in the Homebrew line
- [ ] `.github/workflows/deck.yml` — the generated release notes still explain
      quarantine
- [ ] `ROADMAP.md` — close the M7 notarization and expiry items

## Step 8 — Then, and only then, Sparkle

Auto-update is pointless before notarization: the downloaded update would be
Gatekeeper-blocked exactly like the first install. Immediately after, it is
necessary — otherwise v1.22 ships and nobody who installed v1.21 ever hears
about it. Sparkle signs its appcast with an EdDSA key that is separate from the
Apple certificate; generate it with Sparkle's `generate_keys` and keep the
private half in the repository secrets.

## What $99 does *not* unlock: the Mac App Store

Deck cannot ship on the Mac App Store as architected, and no amount of
paperwork changes that. MAS requires **every** executable inside the bundle to
be sandboxed, and `DeckAgent` exists precisely because the widget sandbox
forbids what it does: running `ps` and `docker`, reading the opencode SQLite
database, running `git log`, installing LaunchAgents. Sandboxing it would delete
OpenBox, GitBox, DevBox, ClipBox and LiveBox's process list — five of twelve
widgets, including the two most distinctive.

The program covers both distribution paths, so nothing is lost by buying it; the
deliverable is a notarized DMG plus a Homebrew cask, which is also what a launch
post should link to.

## Rollback

If notarization keeps failing and a release is urgent, revert the two
`project.yml` settings to `"Apple Development"` / `ENABLE_HARDENED_RUNTIME: NO`,
restore the `-allowProvisioning*` flags, and ship as today — the unnotarized
path stays valid until 2027-08-09. Keep the notarization steps behind
`if: steps.signing.outputs.available == 'true'` so a fork without secrets still
builds.

## Cost and time summary

| Item | Cost | Elapsed |
|---|---|---|
| Apple Developer Program (individual) | $99/yr | hours – 2 days |
| Apple Developer Program (organization) | $99/yr | 1–2 weeks (D-U-N-S first) |
| Steps 1–3 (cert, project, CI) | — | ~half a day |
| Steps 4–5 (verification, second Mac) | — | ~2 hours |
| Steps 6–8 (bundle ID, Keychain, SMAppService, Sparkle) | — | ~2 days |

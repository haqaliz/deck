# PRD critique — keychain-tokens

Pressure-tested 2026-08-26 against the code, not against the prose. Two reds,
five ambers. All fixes have been folded back into `prd.md`.

## 🔴 C1 — The new `FetchOutcome` would be unreachable, and the PRD would ship the exact mistake it cites

The PRD promises a `credentialsUnavailable` outcome so a locked keychain never
reads as "not configured". But **every configured-check in the codebase is
`token.isEmpty` / `isUsable`, evaluated before the fetch**:

- `DeckApp.swift:255` (`prbox.github.isUsable`), `:276` (`prbox.azure.isUsable`),
  `:307` (`!shipbox.token.isEmpty`), `:335` (taskbox), `:168` (openbox)
- `DeckAgent/main.swift:50`, `:133`, `:164`, `:214`, `:234` — "line-for-line" the
  same, as `refreshShipBox`'s own comment says.

If hydrate hands back a plain `String`, a failed keychain read produces `""`,
those branches fall to their `else`, and the code records **`.notConfigured`** —
sending a user with a locked keychain to paste a token they already pasted.
That is the ShipBox C1 mistake (`ROADMAP.md` M6) reproduced verbatim, and the
new outcome would never fire at all.

**Fix (in §5):** hydrate returns a per-key result — `found(String)` / `absent` /
`failed(OSStatus)` — and the host keeps the failed keys. Each gate gains one
line ahead of the existing logic: key failed → record `.credentialsUnavailable`,
skip the fetch. Five keys, two call sites; the `isEmpty`/`isUsable` logic below
it is untouched.

## 🔴 C2 — "load() still returns empty token fields" is false before migration, and the wrong reading loses tokens

Pre-migration, `settings.json` holds the real tokens — that is exactly what
keeps a Deck that has been upgraded but never opened working, because
**`DeckAgent` never writes settings** (only `DeckApp.swift:152` does, confirmed
by grep). If hydrate blanks a field whenever the keychain has no value, the
first agent tick after an upgrade wipes four widgets' credentials from memory
and the user sees "not configured" until they open the app.

**Fix (in §5):** state the precedence explicitly. A keychain value wins when
present; when absent, the value already decoded from the file **survives
untouched**. Hydrate never blanks. Only the app's migration removes a file
value, and only after the keychain write is confirmed.

## 🟡 C3 — A factual error in the value argument

§2 claimed `settings.json` "is read by `scripts/demo-data.sh`". It is not:
that script backs up and rewrites ten **snapshot** files and never touches
settings (`scripts/demo-data.sh:24`). **Fix:** claim removed. The backup /
Time Machine / container-copy argument stands without it.

## 🟡 C4 — Migration order was unspecified, and one order destroys the token

Write-then-scrub and scrub-then-write differ by a lost credential if the
keychain write fails. **Fix (in §5):** write → read back to confirm → only then
blank the field and save. Any failure leaves the file exactly as it was and the
migration retries next launch, which is safe because it is idempotent.

## 🟡 C5 — Adding a `FetchOutcome` case breaks older builds decoding the status file

Left open in §10. **Fix:** resolve it in the plan by giving `FetchOutcome` a
tolerant `init(from:)` that maps an unknown rawValue to `.unreachable` — which
is precisely the rule `FetchStatus.swift:140-142` already states for
unrecognised errors ("never accuse the user of misconfiguring something over an
error we don't recognise").

## 🟡 C6 — The test plan misses the one piece most likely to be wrong

§8 tests the scrub and the migration but not the hydrate-result →
`FetchOutcome` mapping, which is where C1 lives. **Fix (in §8):** make that
mapping a pure function and test all three result kinds across the five
token-bearing sources.

## 🟡 C7 — Keychain deletion on erase is best-effort and silent

`eraseDeckData` already sweeps the container with `try?` and reports nothing;
the five `SecItemDelete` calls will behave the same. Acceptable and consistent —
**fix is to say so** rather than to imply erase is guaranteed.

## Checked and clean

- **No widget reads a token.** The only `token` hits under `DeckWidgets/` are
  OpenBox's `tokenRow` (a label for token *counts*) and a ClipBox preview
  string. The sandboxed extension needs no keychain access — the premise holds.
- **The agent never writes `settings.json`**, so migration cannot race it.
- **No shell invariant is touched**: no widget face, no snapshot schema, no
  cadence change, no container change, no new entitlement, and no widget added
  (so the descriptor-cache version rule does not bite).

# Phase 0 probe: hotkey + panel + tray under hardened runtime

Run 2026-10-10. `probe/main.swift` is throwaway evidence, not product code.
Built with `swiftc -O`, signed `codesign --options runtime` with the Apple
Development identity (team K6X49DG8VF), **no entitlements file**.

## Measured
| Check | Result |
|---|---|
| Hardened runtime on | `flags=0x10000(runtime)` |
| Entitlements | none (`codesign -d --entitlements -` printed none) |
| `NSStatusItem` created (accessory policy) | yes |
| `RegisterEventHotKey` Option-Space | status 0 |
| Positive control: same combo registered twice | status -9878 (`eventHotKeyExistsErr`), so a failed registration IS detectable |
| Carbon handler fires on a real Option-Space chord | yes, 1 of 1 |
| Panel after the chord | visible, `isKeyWindow` true, field first responder |
| Frontmost app after the panel appeared | still Google Chrome (not stolen) |
| Command-Space registration | status 0 (see caveat) |

## Not proven by this run
- **Accessibility.** `AXIsProcessTrusted` was true, but that is inherited from
  the terminal that launched the probe, and the self-test needed it only to
  *post* the chord. It says nothing about whether registering needs it. The
  clean check is launching the probe from Finder/Login, where no terminal
  grant applies, and seeing no prompt.
- **Full-screen apps and other Spaces.** Not exercised; needs a human at the
  screen.
- **Typing into the field** and Esc/click-away dismissal. Key-window status was
  measured, keystrokes were not.
- **Command-Space returning 0 does not mean it would fire**: Spotlight owns
  that chord. Treat "registered OK" as "no conflict reported", not "will win".
  Not tested whether it fires.
- `frontmostApplication` was read immediately after `makeKeyAndOrderFront`; it
  could lag, so re-read after a short delay in the manual run.

## Verdict so far
No entitlement, no TCC prompt text seen, registration works and conflicts are
detectable. The red item is **not yet closed**: the three manual checks above
(Finder launch with no prompt, full-screen/Space, typing) remain.

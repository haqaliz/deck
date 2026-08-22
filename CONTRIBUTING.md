# Contributing to Deck

Thanks for looking. Deck is a single native macOS app shipping one WidgetKit
extension with twelve widgets. It is small on purpose — a contribution that
keeps it small is worth more than one that grows it.

## Development setup

You need macOS 15+, Xcode 16+, and [xcodegen](https://github.com/yonaskolb/XcodeGen):

```bash
brew install xcodegen
git clone https://github.com/haqaliz/deck.git && cd deck
xcodegen generate --spec native/project.yml
```

Build and install:

```bash
xcodebuild -project native/Deck.xcodeproj -scheme DeckApp -configuration Release \
  -derivedDataPath native/build.noindex -allowProvisioningUpdates \
  -allowProvisioningDeviceRegistration build

rm -rf /Applications/Deck.app
cp -R native/build.noindex/Build/Products/Release/Deck.app /Applications/
open /Applications/Deck.app
scripts/lsclean.sh          # after EVERY release build — see below
```

**Signing.** You need a real Apple identity; ad-hoc and self-signed extensions
are rejected by `pluginkit` and will never appear in the Widget Center. A free
Apple ID works for local development.

Run the tests:

```bash
xcodebuild test -project native/Deck.xcodeproj -scheme DeckSharedTests \
  -derivedDataPath native/build.noindex CODE_SIGNING_ALLOWED=NO
```

## Project layout

```
native/
  DeckApp/        host app: settings window (a tab per widget), agent installer
  DeckWidgets/    WidgetKit extension: 12 widgets + Loaders/ (mach, getifaddrs, IOKit)
  DeckAgent/      silent CLI: refreshes sandbox-blocked snapshots, then exits
  Shared/         DeckSettings (Codable), snapshots + stores, host-only samplers
  SharedTests/    XCTest over the Shared parsers — runs on CI
scripts/          repair + soak utilities
docs/planning/    a PRD and plan per feature
```

## The two data paths

This is the core design, and a change that ignores it will not work:

1. **Sandbox-safe, self-sampled** — LiveBox, NetBox and BatBox read mach,
   getifaddrs and IOKit directly inside the widget.
2. **Sandbox-blocked, agent-pumped** — the widget sandbox forbids subprocesses
   and reading other apps' data. `DeckAgent` (a LaunchAgent, every 60s) reads
   those and writes JSON snapshots into the widget's container; the widgets
   render the snapshots.

If your data source needs a subprocess, another app's files, or the network,
it belongs in the agent.

## Adding a widget

1. Copy an existing widget in `native/DeckWidgets/` (GitBox or NetBox are the
   simplest) and register it in `DeckWidgets/DeckWidgets.swift`.
2. Add a `<Widget>Settings` struct to `Shared/DeckSettings.swift` — it **must**
   decode tolerantly (`decodeIfPresent` for every field) — and a settings tab
   in `DeckApp/DeckApp.swift`.
3. If the data is sandbox-blocked, add a snapshot model + store in `Shared/`
   and sample it in `DeckAgent/main.swift`.
4. **Bump `CFBundleShortVersionString` and `CFBundleVersion` in
   `native/project.yml`.** WidgetKit caches the widget descriptor set per
   extension version; a new widget added without a version bump never appears
   in the Widget Center, and everything else looks healthy while it happens.
5. Register it in `README.md` and `ROADMAP.md`.
6. Add tests for any parser or formatter to `native/SharedTests/`.
7. Rebuild, re-add the widget from the gallery, and check all three sizes.

## Traps that will cost you a day

- **Re-run `xcodegen` after adding any source file.** It enumerates files at
  generation time, so a new test file is silently not compiled and the suite
  still reports success.
- **Never `rm -rf` the widget container.** The SIP-protected metadata plist
  survives, so containermanagerd never rebuilds the skeleton and *every* widget
  renders as an empty rounded rect while codesign, `pluginkit` and
  LaunchServices all look healthy. Repair with `scripts/container-repair.sh`.
- **Run `scripts/lsclean.sh` after every release build.** `build.noindex` hides
  the directory from Spotlight but xcodebuild still registers the dev copy with
  LaunchServices, and a stale registration makes every widget render as grey
  placeholder blocks.
- **Watch timeline archive size.** A widget emitting many timeline entries can
  produce an archive WidgetKit accepts and then draws as an empty widget. Check
  `~/Library/Containers/com.deck.app.widgets/Data/SystemData/com.apple.chrono/timelines/`.

`CLAUDE.md` has the long-form version of each of these.

## Style

- Metrics loaders return pure data; stores own timers; views own layout.
- Widgets share a visual language: rounded system fonts, monospaced digits,
  colored-dot metric rows, hidden chart axes, section titles tracked 1pt.
- Match the comment density of the file you are editing. Comments explain why,
  not what.
- No settings UI inside widgets — WidgetKit has none. Settings live in the app.

## Pull requests

- One logical change per PR, with a title that names the widget or feature.
- Include tests for parsers, formatters and decoders.
- Say how you verified it: which widget, which sizes, re-added from the gallery.
- CI must be green. It builds Release and runs `DeckSharedTests`.

## Privacy expectations

Deck reads personal data — clipboard, calendars, work items, repositories. Any
contribution that touches those must keep the existing rules: nothing leaves the
machine except to the service the user configured, snapshots stay in the widget
container, and anything that could hold a secret is filtered rather than stored.
Redact real data from screenshots in issues and PRs.

## Security

Do not open a public issue for a vulnerability. Email the maintainer using the
address in the commit history.

## License

By contributing you agree that your contributions are licensed under the
Apache License 2.0, the same as the rest of the project.

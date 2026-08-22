## What this changes

## Why

## How it was verified

<!-- Deck's failure modes are mostly invisible to the compiler. Say what you
     actually looked at. -->

- Widget(s) touched:
- Sizes checked: [ ] small  [ ] medium  [ ] large
- [ ] Re-added the widget from the gallery after installing (widgets must not
      regress between builds)
- [ ] `xcodegen generate` re-run if any source file was added
- [ ] `DeckSharedTests` pass
- [ ] Version bumped in `native/project.yml` (**required** when adding a widget)
- [ ] `README.md` / `ROADMAP.md` updated if user-facing

## Notes for the reviewer

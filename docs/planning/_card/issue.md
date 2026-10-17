# landing-page (inline brief)

Source: `dbf feat landing-page`, handed off by `deck-next` (2026-10-17).

## Brief

Build the landing page for Deck's launch URL — the last un-gated item in M7
(`ROADMAP.md:819`). M9's notarization, expiry-cliff, bundle-identifier and
Sparkle work all wait on the paid Apple Developer Program, so this is the only
launch-readiness piece buildable today.

Deck is a set of fourteen small, beautiful macOS desktop widgets delivered as one
native app plus a quick-search panel. The landing page is the front door for the
launch URL: it should present that story and get a visitor to install.

## Scope to settle in the PRD (the ROADMAP gives a single line)

- **Hosting** — GitHub Pages served from `docs/` in this repo, a `gh-pages`
  branch, or a separate repo.
- **Content** — the widget story (lifted from `README.md`: the fourteen widgets,
  screenshots in `docs/screenshots/`, the Deck mark in `docs/deck.svg`), and
  what a visitor can do (download the DMG, or `brew install --cask`).
- **Install copy** — must stay byte-consistent with `README.md` and
  `homebrew/deck.rb`, including the rule that the `xattr -dr
  com.apple.quarantine` line runs **before** the first launch (`README.md:88-104`)
  and the note that both steps disappear on notarization.

## Caveat from the recommender

This reuses **none** of the widget shell and the docs are thin (a one-line
ROADMAP entry, no planning doc). Confirm it is worth a unit of work versus
waiting for M9, and do not let the install instructions drift from `README.md`
and the cask.

# Understanding — landing-page

## What the work is really asking

Build the **front door for the launch URL**: a page that tells Deck's story
(fourteen macOS widgets in one WidgetKit extension, plus the Search panel) and
gets a visitor to install it. It is the last un-gated item in M7 launch
readiness (`ROADMAP.md:819`); everything else in M7 is ticked and M9 is gated
on the paid Apple Developer Program. This is **marketing copy + a static page**,
not shell code — it touches no `native/` source.

## What already exists (the content the page must stay consistent with)

| Thing | File | What it gives the page |
|---|---|---|
| Widget story | `README.md` (32.7 KB) | The fourteen widgets and what each shows; the install steps; the Search prefixes table |
| Install copy | `README.md:69-104` | `brew install --cask haqaliz/deck/deck` → `xattr -dr …` → `open`, then Edit Widgets |
| Cask + caveats | `homebrew/deck.rb` | Same sequence, version `1.54`, the "launch-before-xattr deletes the app" warning |
| Release notes | `.github/workflows/deck.yml:167-189` | The **third** copy of the install text, with the DMG URL pattern |
| Screenshots | `docs/screenshots/A1–A6.png`, `deck-logo.png` | Six widget montages + a logo |
| Mark | `docs/deck.svg` | The Deck "D" mark (also used for the tray icon) |
| Release asset | GitHub Releases | `.../releases/download/v1.54/Deck-v1.54.dmg` + `SHA256SUMS.txt` |

## Key findings

- **There is no site today.** No `index.html`, no `CNAME`, no `.nojekyll`, no
  `gh-pages` workflow, and `GET /repos/haqaliz/deck/pages` returns **404** —
  GitHub Pages is not configured.
- **`docs/` is not just assets.** The repo's `docs/` holds `planning/` (internal
  planning docs) *and* `screenshots/` + `deck.svg` (referenced by the README via
  relative paths). Serving a Pages site **from `docs/`** would publish the whole
  `planning/` tree as the website — undesirable even though the repo is already
  public. A `gh-pages` branch or an Actions-built site from a dedicated `site/`
  source dir avoids this.
- **The install instructions are already duplicated three times** (`README.md`,
  `homebrew/deck.rb` caveats, `deck.yml` notes) and they are **not** byte
  identical — the wording differs while the sequence and the order rule agree.
  Adding a fourth copy is a real drift risk: the page must reproduce the
  sequence and the "xattr *before* first launch" rule, and the notarization
  release must remember to update it.
- **No JS/build tooling exists** in the repo (no `package.json`). A build-step
  site (Astro/Next) would add a toolchain; a plain static HTML+CSS page has no
  build and is trivially verifiable.
- **The README is the source of truth and is long.** The page should distill it
  (hero + widget grid + install), not duplicate all 32 KB.

## Shell / invariant check

No `native/` code is touched, so the widget-shell invariants (material card,
dynamic height, corner mask, panel behavior) do not apply. The invariant that
*does* apply is the install-sequence correctness from CLAUDE.md ("Launching a
quarantined Deck deletes it, and `--no-quarantine` is gone") — the page must not
invent a `--no-quarantine` command or reorder the steps.

## Ambiguities / open questions for the interview

1. **Hosting** — GitHub Pages from `docs/` (leaks `planning/`), a `gh-pages`
   branch, an Actions-built `site/`, or a separate repo?
2. **Tech** — plain static HTML+CSS (no build) vs. a generator?
3. **Content depth** — how much of the widget story: a hero + all fourteen
   widgets + install, or a shorter page?
4. **URL** — `haqaliz.github.io/deck` vs. a custom domain?
5. **Install CTA** — DMG download link and Homebrew, both? Latest-release link
   (rolling) vs. a pinned version?
6. **Verification** — how is a static page proven good without a browser in CI?

# PRD — landing-page

**Slug:** `landing-page`
**Type:** feat (launch readiness, M7 — `ROADMAP.md:819`)
**Status:** draft for review

## 1. Restate the ask

Build a static marketing page for Deck's launch URL — the front door that
presents Deck (fourteen macOS widgets in one WidgetKit extension, plus the
Search panel) and gets a visitor to install it — at
`https://haqaliz.github.io/deck`.

## 2. User-visible spec (the "front face")

One page, top to bottom. Content is distilled from `README.md`; the page does
**not** try to reproduce the README.

| # | Section | Content |
|---|---|---|
| 1 | **Hero** | The Deck mark (`docs/deck.svg`), "Deck", the one-line pitch — *"Fourteen small, beautiful macOS desktop widgets in one native app"* — and two CTAs: **Download for macOS** and **`brew install --cask haqaliz/deck/deck`** (copy-to-clipboard). |
| 2 | **Screenshots** | 2–3 of the montages (`docs/screenshots/A1.png` … `A6.png`), as a responsive pair/trio. |
| 3 | **The widgets** | A grid of fourteen cards, each = name + a one-line "shows" line distilled from the README table. |
| 4 | **Search** | One short block: ⌥Space opens a floating search panel over the services the widgets already use; a couple of example prefixes (`pr `, `mkt `, `cal `). |
| 5 | **Install** | The install block, in order: DMG download **or** Homebrew; then the `xattr -dr com.apple.quarantine /Applications/Deck.app` line and the "run this **before** the first launch" warning; then "right-click the desktop → Edit Widgets…". |
| 6 | **Footer** | Apache-2.0, link to the GitHub repo, and a one-line note that Deck is not notarized yet (macOS quarantines it) so both install steps disappear on the M9 release. |

Behavior: no JavaScript except the Homebrew copy-to-clipboard button (and that
degrades to a visible, selectable command if scripting is off). Light and dark
follow `prefers-color-scheme` so it reads like a native macOS page.

### The fourteen widget cards (one line each, distilled from `README.md:50-63`)

| Widget | One line |
|---|---|
| LiveBox | CPU / MEM / DISK with a live chart, top processes and threshold coloring |
| OpenBox | opencode usage: tokens, cost, 14-day chart, models, sessions |
| NetBox | per-interface up/down rates and history |
| BatBox | battery level and time remaining, plus Bluetooth accessory batteries |
| GitBox | commits per day, today's count, streak and active repos |
| DevBox | open TCP ports and running Docker containers |
| ClipBox | clipboard history, local only |
| WeatherBox | conditions and a 3-day forecast for your location |
| ClockBox | world clocks for up to six cities |
| ShipBox | GitHub Actions runs across your repos, merged newest-first |
| TaskBox | Azure DevOps work items: open count, current sprint, board lanes |
| CalBox | TODAY and TOMORROW events from every calendar macOS syncs |
| PRBox | your open PRs and the ones awaiting your review, GitHub + Azure DevOps in one queue |
| MarketBox | crypto, fiat, gold and US stocks in one display currency |

## 3. "Data source" — static content and its sources of truth

This page has no runtime data. Its content is authored once; the load-bearing
question is **drift**, not fetching.

| Value | Source of truth | Rule |
|---|---|---|
| Widget names + one-liners | `README.md:50-63` | Distilled; if a widget's description changes, the page follows |
| Install sequence | `README.md:69-104`, `homebrew/deck.rb` caveats, `.github/workflows/deck.yml:167-189` | The page reproduces the **sequence and the order rule**; it must never invent `--no-quarantine` |
| Download URL | GitHub Releases | Link the rolling **latest release page** (`/releases/latest`), because the DMG asset name carries the version and a pinned link would go stale |
| Screenshots, mark | `docs/screenshots/*`, `docs/deck.svg` | Copied into the deployed artifact at deploy time (see §4); not duplicated in git |

Refresh cadence: none (static). The only "refresh" event is a Deck release that
changes the install steps — the notarization release (M9) is the next one, and
it must update this page alongside `README.md`, the cask and the release notes.

## 4. Shell fit / hosting

No `native/` code is touched, so the widget-shell invariants do not apply. The
relevant structure:

- **Source** lives in a new `site/` directory at the repo root: `index.html`,
  `styles.css` (relative URLs only, so it works at `/deck/` and from a local
  server).
- **Assets** (`docs/screenshots/*.png`, `docs/deck.svg`) are **staged into the
  artifact at deploy time** by a small `scripts/build-site.sh` that copies
  `site/` plus those files into a staging dir — so the images keep one home in
  git and the page links them as `assets/…`. No build toolchain: the script
  only copies.
- **Deploy** is a new `.github/workflows/pages.yml` using
  `actions/upload-pages-artifact` + `actions/deploy-pages`, triggered on pushes
  to `master` that touch `site/**` (and `workflow_dispatch`). This leaves
  `docs/planning/` unpublished.
- **One-time repo setting:** Pages → Source = **GitHub Actions** (the user flips
  this once; the workflow cannot).
- **Local preview:** `scripts/build-site.sh` then `python3 -m http.server` over
  the staging dir.

### Invariant that does apply

The install order, from CLAUDE.md ("Launching a quarantined Deck deletes it,
and `--no-quarantine` is gone"): `brew install --cask` (or drag the DMG) →
`xattr -dr com.apple.quarantine /Applications/Deck.app` → **then** launch. The
page must state the warning in that order and never present `--no-quarantine`.

## 5. Non-goals

- **Not a docs site.** `docs/planning/` is not published, linked or indexed.
- **No build framework** (no Astro/Next/Tailwind toolchain), no `package.json`.
- **No analytics, telemetry, cookies or a backend** — consistent with Deck's
  "no Deck server" privacy stance (`README.md:360-362`).
- **No auto-update / Sparkle** — that is M9.
- **Not the source of truth for docs.** It links to the repo and the README; it
  does not replace or re-render them.
- **No custom domain** (chosen: `haqaliz.github.io/deck`).
- **Does not rewrite `README.md`** beyond, at most, one link to the site.

## 6. Decisions taken (interview, 2026-10-17)

1. Hosting: `site/` source + GitHub Actions deploy to Pages.
2. Build: plain static HTML + CSS, no build toolchain.
3. Content: hero + all-fourteen widget grid + install (+ Search block, footers).
4. Install CTA: DMG download **and** Homebrew.
5. URL: `haqaliz.github.io/deck` (relative URLs throughout).

## 7. Acceptance criteria

- The Pages workflow deploys on push to `master`; the site answers at
  `https://haqaliz.github.io/deck/` and every asset loads (no 404s).
- The page names all fourteen widgets.
- The install block contains, in order, the DMG/Homebrew route, the `xattr`
  line, and the before-first-launch warning, and contains **no**
  `--no-quarantine`.
- A committed check asserts those strings (see verification in the plan), so a
  later edit that drops the warning or invents the flag fails.
- Light and dark both render legibly; the page is usable at phone width.

## 8. Verification (to be detailed in the plan)

- `scripts/build-site.sh` runs locally and produces a staging dir with assets.
- A shell check (run by the pages workflow, and available as
  `scripts/check-site.sh`) greps the built page for the required install strings
  and the absence of `--no-quarantine`.
- Manual: open the staging dir over a local HTTP server and check both
  appearances and the two CTAs.
- Post-deploy: fetch the live URL and confirm HTTP 200 and the asset references.

## 9. Self-critique (2026-10-17)

Pressure-tested against the widget-shell checklist. A landing page is not a
widget, so the shell invariants (material card, dynamic height, corner mask,
behind-windows level, settings persistence) are out of scope; the one invariant
that *does* apply — the install order — is covered in §4.

**🔴 Red: none.** No shell invariant is at risk and there is no data-source
question (the page is static; §3 answers drift instead). Repo visibility was
checked: `haqaliz/deck` is **public**, so Pages is available on the free plan —
a private repo would have blocked the whole approach.

**🟡 Amber, with fixes:**

1. **The workflow cannot enable Pages.** `actions/deploy-pages` fails until
   Pages → *Source = GitHub Actions* is set by hand. *Fix:* a plan step and a
   verification step ("enable → push → 200"); the workflow's first failure names
   it. This is the one item the acceptance criteria cannot meet without an
   out-of-repo action.
2. **The deploy trigger misses the assets.** Screenshots and the mark live in
   `docs/screenshots/**` / `docs/deck.svg`, so a push that only changes a
   screenshot would not re-deploy. *Fix:* trigger on `site/**`,
   `scripts/build-site.sh`, `docs/screenshots/**`, `docs/deck.svg` and the
   workflow file itself.
3. **"No build" vs. a `build-site.sh`.** The chosen answer was plain static, no
   build toolchain. The script only copies, but the name implies more. *Fix:*
   name it `scripts/stage-site.sh`, keep it dependency-free (no JS/npm), and run
   the string checks against the **staged** artifact (what actually ships), not
   `site/`.
4. **The check proves presence, not parity.** Grepping for the install strings
   (and the absence of `--no-quarantine`) proves the page *has* them, not that
   they match `README.md`. *Fix:* keep the grep as a floor, add a short list of
   the four install copies (README, `homebrew/deck.rb`, `deck.yml` notes, this
   page) in the install section as a human prompt for the next release, and
   optionally grep all four for the `xattr` line.
5. **Download label vs. target.** `releases/latest` is a page, not a `.dmg`; a
   button labelled "Download for macOS" that opens a page is a mismatch. *Fix:*
   label it *"Download — latest release"* (or read the cask version in the stage
   script and link the versioned DMG directly; the rolling link is the honest,
   low-maintenance default).
6. **Copy-to-clipboard degrades.** *Fix:* the Homebrew command is always present
   as a selectable `<code>`; the button only copies it. Pinned in acceptance.
7. **Found in passing, not part of this task:** the repo's GitHub description is
   stale — *"Twelve native macOS desktop widgets…"* (there are fourteen) — and
   `homepageUrl` is empty. *Fix (optional, 1 command, after the site is live):*
   `gh repo edit haqaliz/deck --description "…" --homepage https://haqaliz.github.io/deck`.
8. **Project-page paths.** The site is served under `/deck/`; a stray absolute
   `/asset.png` would 404. *Fix:* relative URLs throughout; the acceptance test
   fetches the root and one asset.
9. **Widget one-liners drift from the README over time.** Accepted — a marketing
   page is a snapshot; only the install strings are hard-checked.

**No 🔴; nine 🟡, all with concrete fixes.** The spec stands with the fixes in
3, 5 and 6 folded in.

## Open questions

None outstanding — the five from the interview are resolved in §6.

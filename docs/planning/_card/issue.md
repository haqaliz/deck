# Source brief: crash-robustness-pass (inline, from deck-next handoff)

M4 crash/robustness pass for Deck: run the extension 24h and fix any crashes,
leaks, or memory growth. All nine widgets are shipped (ROADMAP.md M3
complete), so this closes the last open milestone.

Plan (draft): define the soak method (widgets kept visible; Leaks instrument
on the DeckWidgets process, or repeated timeline invalidation), instrument if
needed, fix what surfaces, and keep the 60s timeline floor and shell
invariants untouched.

Caveats (from deck-next):

- GPU/ANE stays blocker-deferred (no public Apple Silicon API,
  docs/planning/livebox-per-core-cpu/prd.md:94) — do not pull that item in.
- Hidden widgets are throttled by WidgetKit, so a 24h soak must keep widgets
  on-screen to be meaningful.
- Verify via build + install + re-add from the gallery after any change.

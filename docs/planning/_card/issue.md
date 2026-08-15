# Inline brief: openbox-session-list

Source: deck-next handoff (2026-08-15).

Add OpenBox's session drill-down slice: a top-sessions list (title/command,
tokens, model, relative time) on the large face, top-N capped by a settings
count (reuse the tool-usage count stepper pattern). Data is already local —
the agent reads the opencode DB every 60s and DeckSharedTests covers the
session/part schema — so this is snapshot field + parser SQL + list layout
only, no new data source. Caveat: WidgetKit on macOS has no in-widget
navigation, so "drill-down" is a large-face list (optionally a show/hide
setting), not tap-through. Follow the shipped tool-usage slice as the template
and keep the scratch-package TDD pattern until merged.

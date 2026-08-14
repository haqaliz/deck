# Inline brief: HomeBox (weather + world clock)

Source: deck-next handoff (2026-08-14).

HomeBox: weather + world clock widget (pending M3, ROADMAP.md:47). Copy the
NetBox/GitBox shell; front face shows conditions + temp for your location plus
2–3 timezones, settings tab picks location (wttr.in by city/geo) and zones
(default: local + UTC).

Follow the proven openbox-remote pattern for the bounded URLSession fetch
inside the widget with loader-error degrade states; parse wttr.in JSON in a
scratch HomeBoxCore package with fixture tests (the JSON shape is an external
contract).

Caveat: network-only front face — verify widget timeline fetching on macOS
early (probe before PRD), and timezone rows must render from local TimeZone
data with zero fetch.

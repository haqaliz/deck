# Split HomeBox into WeatherBox + ClockBox

Type: feat
Branch: feat/clockbox/aliz
Source: inline brief (no GitHub issue)

## Brief

HomeBox currently carries two unrelated concerns: weather (conditions +
3-day forecast, fetched from wttr.in by DeckAgent) and world clocks.
Split them.

1. **Rename HomeBox -> WeatherBox.** Weather and forecast only. The clock
   half is removed from this widget. Existing user settings and the agent
   snapshot must survive the rename (migration, not a reset).

2. **New ClockBox.** World clocks inspired by the native macOS World Clock
   widget: an analog clock face per city, up to 4, with the city name,
   a "Today"/relative-day line, and a UTC offset label ("-7:30", "+0HRS").
   Cities are user-selected in the Deck settings window.

## Reference

Native macOS World Clock widget (medium): four analog faces in a row.
Each face: white dial, black hour/minute hands, orange second hand.
The user's own local-zone city renders as a dark dial with white hands.
Below each face: city name (bold), day ("Today"), offset ("-7:30").

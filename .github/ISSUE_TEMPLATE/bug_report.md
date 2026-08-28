---
name: Bug report
about: A widget, the settings window, or the background agent behaves wrong
title: "[bug] "
labels: bug
---

## Which widget

<!-- LiveBox / OpenBox / NetBox / BatBox / GitBox / DevBox / ClipBox /
     WeatherBox / ClockBox / ShipBox / TaskBox / CalBox — or the Deck app itself. -->

## What happened

<!-- The wrong behavior, and what you expected instead. -->

## Steps to reproduce

## Environment

- Deck version (Deck app → About, or the release tag):
- macOS version:
- Widget size affected (small / medium / large / all):
- Apple silicon or Intel:

## Checks

<!-- These three catch most reports. Please run them before filing. -->

- [ ] `pluginkit -m -i com.deck.app.widgets` lists the extension
- [ ] `stat -f '%Sm' ~/Library/Containers/com.deck.app.widgets/Data/Library/Application\ Support/Deck/processes.json`
      is recent (the agents' liveness check — `launchctl list` shows nothing
      even when they are healthy)
- [ ] I ran `scripts/lsclean.sh` (fixes grey placeholder blocks in every widget)

## Logs

<!-- log show --last 5m --info --predicate 'subsystem == "com.deck.agent"'
     Redact tokens, calendar entries, work item titles and hostnames. -->

```
```

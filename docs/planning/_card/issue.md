# Brief: spotlight-remote-search (ROADMAP M10, second item onward)

Stacked on `feat/spotlight-shell/aliz` (the shell is not merged yet).

Add network-backed sources to the Spotlight panel. The shell's providers are
synchronous functions over local snapshots; remote sources cannot be, because
typing must not fire a request per keystroke and Deck already hits rate limits
(CoinGecko 429s, GitHub's 30 searches/min, Yahoo bursts — see CLAUDE.md).

This slice: the shared remote-search layer (debounce, min length, per-source
floor, per-query cache, 429 degrades one section, stale-response safety, async
panel sections) plus its first user, TaskBox search: any task of any age by
title, tag or id, via WIQL against the account TaskBox is configured with.

Later slices reuse the layer: PRBox, GitBox/CalBox, ShipBox/MarketBox.
Defaults agreed 2026-10-10: prefixes task/pr/commit/cal/run/mkt; every project
on the account, closed items included; 300 ms debounce, 2 chars minimum;
Enter opens in the browser, Cmd-Return copies the link.

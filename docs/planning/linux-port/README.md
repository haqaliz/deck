# Deck Linux & Raspberry Pi port

Planning artifacts and the start of the second native app.

- [`prd.md`](prd.md) — product scope, owner decisions, v1 widgets, platform
  limits and success criteria.
- [`architecture.md`](architecture.md) — Rust/GTK4 stack, processes, workspace,
  snapshot contract, platform backends, credentials, packaging and risks.
- [`milestones.md`](milestones.md) — L0-L8 with tasks, acceptance, estimates and
  the v1 definition of done.
- [`spike.md`](spike.md) — L0 results on the actual Pi 4B.

**Status 2026-11-19:** L0, L1 and L2 are done on the Pi. The code is under
[`linux/`](../../linux/), 22 core + 2 daemon tests green. The GTK4 shell,
layer-shell widget, settings, tray, search panel and labwc shortcut work. Next
is L3: LiveBox, NetBox and DevBox. See [`l2.md`](l2.md).

L0 verified Pi OS Trixie / labwc, layer-shell, `ksni` tray and the labwc
shortcut. KDE, GNOME and X11 had no machine and move to L7.

# Deck Linux & Raspberry Pi port

Planning artifacts and the start of the second native app.

- [`prd.md`](prd.md) — product scope, owner decisions, v1 widgets, platform
  limits and success criteria.
- [`architecture.md`](architecture.md) — Rust/GTK4 stack, processes, workspace,
  snapshot contract, platform backends, credentials, packaging and risks.
- [`milestones.md`](milestones.md) — L0-L8 with tasks, acceptance, estimates and
  the v1 definition of done.
- [`spike.md`](spike.md) — L0 results on the actual Pi 4B.

**Status 2026-11-22:** L0-L13 are done. The code is under
[`linux/`](../../linux/), 126 core + 3 daemon + 6 GUI/platform tests green.
v0.2.0 was the macOS visual-parity pass; v0.3.0 added remote search and
deferred widget work; v0.4.0 added section-card settings, multi-account Azure
credentials, remote log search, stock lookup and container verification; v0.5.0
adds CalBox over CalDAV; v0.6.0 adds the calendar picker, ClipBox and BatBox. See
[`l9.md`](l9.md), [`l10.md`](l10.md), [`l11.md`](l11.md), [`l12.md`](l12.md)
and [`l13.md`](l13.md). The remaining verification gaps
(KDE/GNOME, Pi 5, live API accounts, multi-monitor, CalDAV) are listed in
[`known-limitations.md`](known-limitations.md).

L0 verified Pi OS Trixie / labwc, layer-shell, `ksni` tray and the labwc
shortcut. KDE, GNOME and X11 had no machine and move to L7.

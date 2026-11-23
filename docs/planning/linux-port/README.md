# Deck Linux & Raspberry Pi port

Planning artifacts and the start of the second native app.

- [`prd.md`](prd.md) — product scope, owner decisions, v1 widgets, platform
  limits and success criteria.
- [`architecture.md`](architecture.md) — Rust/GTK4 stack, processes, workspace,
  snapshot contract, platform backends, credentials, packaging and risks.
- [`milestones.md`](milestones.md) — L0-L8 with tasks, acceptance, estimates and
  the v1 definition of done.
- [`spike.md`](spike.md) — L0 results on the actual Pi 4B.

**Status 2026-11-23:** L0-L19 are done; v1.1.2 reflows widgets after live show/hide. The code is under
[`linux/`](../../linux/), 127 core + 3 daemon + 6 GUI/platform tests green.
v0.2.0 was the macOS visual-parity pass; v0.3.0 added remote search and
deferred widget work; v0.4.0 added section-card settings, multi-account Azure
credentials, remote log search, stock lookup and container verification; v0.5.0
adds CalBox over CalDAV; v0.6.0 adds the calendar picker, ClipBox and BatBox; v0.7.0 adds Flatpak; v0.8.0 adds accessory batteries and named accounts; v1.0.0 freezes the widget set; v1.1.0 polishes updates and metrics search. See
[`l9.md`](l9.md), [`l10.md`](l10.md), [`l11.md`](l11.md), [`l12.md`](l12.md)
[`l13.md`](l13.md) [`l14.md`](l14.md) [`l15.md`](l15.md), [`l16.md`](l16.md), [`l17.md`](l17.md), [`l18.md`](l18.md) and [`l19.md`](l19.md). The remaining verification gaps
(KDE/GNOME, Pi 5, live API accounts, multi-monitor, CalDAV) are listed in
[`known-limitations.md`](known-limitations.md).

L0 verified Pi OS Trixie / labwc, layer-shell, `ksni` tray and the labwc
shortcut. KDE, GNOME and X11 had no machine and move to L7.

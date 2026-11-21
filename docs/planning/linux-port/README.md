# Deck Linux & Raspberry Pi port

Planning artifacts and the start of the second native app.

- [`prd.md`](prd.md) — product scope, owner decisions, v1 widgets, platform
  limits and success criteria.
- [`architecture.md`](architecture.md) — Rust/GTK4 stack, processes, workspace,
  snapshot contract, platform backends, credentials, packaging and risks.
- [`milestones.md`](milestones.md) — L0-L8 with tasks, acceptance, estimates and
  the v1 definition of done.
- [`spike.md`](spike.md) — L0 results on the actual Pi 4B.

**Status 2026-11-21:** L0-L11 are done. The code is under
[`linux/`](../../linux/), 127 tests green. v0.2.0 was
the macOS visual-parity pass; v0.3.0 added remote search and deferred widget
work; v0.4.0 adds section-card settings, multi-account Azure credentials,
remote log search and stock lookup, and verifies wlroots, X11 and Secret
Service in containers. See [`l9.md`](l9.md), [`l10.md`](l10.md) and
[`l11.md`](l11.md). The remaining verification gaps (KDE/GNOME, Pi 5, live
API accounts, multi-monitor) are listed in
[`known-limitations.md`](known-limitations.md).

L0 verified Pi OS Trixie / labwc, layer-shell, `ksni` tray and the labwc
shortcut. KDE, GNOME and X11 had no machine and move to L7.

# M11 — Infra visibility (PRD)

**Status:** slices 1–3 built 2026-11-17; installed verification open.
**Source brief:** `docs/planning/_card/issue.md`.

## Problem

Deck shows the machine it runs on and the services around it, but the two
places that answer "is production healthy?" and "is any machine in trouble?"
are browser tabs: Kibana for Manifold logs and Grafana for the fleet. Both are
checked many times a day, and both need a tailnet/VPN and a login.

## Goal

Two desktop widgets, each with one metric story, that answer those questions
at a glance and open the full view on click:

- **LogBox** — Manifold errors/warnings from Elastic, with a Kibana link.
- **MetricBox** — machine health from Grafana, with a Grafana link.

Non-goals: replacing either dashboard, arbitrary queries, alert management,
writes of any kind, or raw log browsing beyond the newest five errors.

## Users and jobs

- **On-call / backend** — "did the deploy make errors jump?" (LogBox).
- **Fleet owner** — "which machine is busy, full or silent?" (MetricBox).
- **Power/cost** — "what are the machines drawing and costing?" (MetricBox).

## Data contracts (verified 2026-11-17)

### Elastic

- Cluster `manifold-logs`, ES 9.5.3, data streams `logs-manifold-prd` and
  `logs-manifold-stg`.
- Kibana `https://x300.tail970481.ts.net`, space `prd`; data view id and title
  are both `logs-manifold-prd`.
- Direct ES at `:9200`, API-key auth (`Authorization: ApiKey …`).
- Fields: `@timestamp`, `service.name`, `log.level`, `log.logger`,
  `host.name`, `container.name`, `manifold.message_template`, `message`,
  `error.stack_trace`.
- Measured: 10.58M docs/24h PRD (8.70M info, 1.88M warn, 5,075 error); 15m
  errors by service ~9ms; 15m all levels ~2s; 24h errors-only trend ~4.4s;
  newest five errors ~17ms.

### Grafana

- 13.2.3 at `https://monitoring.4si8analytics.com`, org Manifold.
- Datasources: VictoriaMetrics (default Prometheus; uid discovered at runtime),
  Elasticsearch PRD/STG.
- Hosts: x201–x205, x300, x301 (node exporter, NVIDIA, cAdvisor).
- Dashboards used for links: `fleet-overview`, `power`, `top-agents`,
  `manifold-logs`.
- Measured: 24h CPU for seven hosts ~1.0s / 68 KB / 7×289 points; an instant
  query returns one frame per host with `labels.host`.

## Decisions (user, 2026-11-17)

- Two widgets, not one combined face.
- LogBox first; direct Elastic, not through Grafana's proxy.
- URL stored on the `CredentialAccount` (one per provider), selected per widget.
- Environment per widget: PRD default, STG selectable.
- Log text defaults to templates + counts; raw message and full-line modes are
  opt-in.
- Time windows: small 15m, medium/large 24h, both editable.
- MetricBox shows all seven hosts by default, hideable.
- Every face is selectable in settings; defaults are Prod health and Fleet
  health.
- The current keys were accepted for this build. Read-only rotation remains
  recommended (Elastic `x132` is `manifold_admin`; Grafana `sa-1-x132` is Admin).

## Faces

### LogBox

| Face | Content |
|---|---|
| Prod health (default) | error/warn counts for the small window, 24h error trend, worst service |
| What's broken | top error templates, newest error time |
| Single service | all queries narrowed to the service in settings |
| Grafana panels | services plus the trend, mirroring the Manifold logs dashboard |

Text modes: templates + counts (default), latest message, full log lines (five).
Rows link to Kibana Discover with the environment index, time range and filter.

### MetricBox

| Face | Content |
|---|---|
| Fleet health (default) | every visible host, silent first then busiest: CPU/RAM/disk; GPU and watts on large |
| Single host | CPU/RAM/disk, GPU/VRAM/temperature, uptime, 24h CPU sparkline |
| Power & cost | current watts, 24h kWh, monthly estimate (rate default 0.12 USD/kWh) |
| Top agents | containers ranked by VRAM, GPU, CPU |
| Alerts | firing Grafana alerts, or a quiet "none" state |

Rows link to the matching Grafana dashboard with the time range and, for a
single host, `var-host`.

## Failure states

- No account picked → "Pick an Elastic/Grafana account in settings".
- Keychain locked → "can't read saved credentials", never "paste a token".
- Tailscale down / 5xx / timeout → "Can't reach Elastic/Grafana", last-good
  snapshot stays visible with its age.
- Unreadable payload → "Unexpected Elastic/Grafana response".
- A slow 24h query failing does not blank the fast counts; the previous trend
  is reused and the note says it is unavailable only when there is none.

## Security and privacy

- Read-only keys only; no write endpoints are called.
- URLs are on the account, so they are visible to the app and agent but never
  embedded in a widget snapshot.
- Tokens are hydrated from the Keychain host-side and never encoded into
  `settings.json`, snapshots, or logs.
- Deep links are filtered by `DeckLink.webURL` at the widget boundary.
- Log text is off by default: templates and counts do not put customer data,
  IDs or URLs on the desktop.

## Acceptance

- Both faces render live data on small/medium/large from a Release install.
- Every face and text mode in the settings tabs changes the face within a tick.
- A dead service, a bad key and an empty window each show their own sentence.
- Deep links open the matching Kibana/Grafana view.
- No token or raw customer data appears in a snapshot file.
- Shared tests green; widget gallery shows both widgets.

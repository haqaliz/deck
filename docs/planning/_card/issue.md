# M11 — Infra visibility (inline brief)

Two new Deck widgets on services already in daily use, plus the shared
credential/settings plumbing both need.

## LogBox (Elastic)

- Data: `logs-manifold-prd` / `logs-manifold-stg` on `https://x300.tail970481.ts.net:9200`
  (ES 9.5.3). Kibana at `https://x300.tail970481.ts.net` (space `prd`).
- Direct queries with a read-only Elastic API key.
- Face presets, default **Prod health**: error/warn counts, 15m live, 24h error
  trend, worst service, top template, last error.
- Text mode defaults to templates + counts; raw message opt-in.
- Kibana Discover deep link with index, range and filter.
- Environment picked per widget (PRD default, STG selectable).

## MetricBox (Grafana)

- Data: Grafana 13.2.3 at `https://monitoring.4si8analytics.com`, org Manifold.
  VictoriaMetrics datasource uid `P4169E866C3094E38`.
- Seven hosts x201–x205, x300, x301; all shown by default, hideable.
- Face presets, default **Fleet health** (CPU %, RAM %, disk %, last seen,
  worst-first); also Single host, Power & cost, Top agents, Alerts.
- Grafana deep link with `var-host` and range.
- One alert rule: "House machine not reporting".

## Shared

- New `CredentialKind` `.elastic` and `.grafana`; URL stored on the
  `CredentialAccount`, not the widget.
- Settings → Credentials form: URL(s), token, Test connection.
- Agent-pumped snapshots, 60s cadence; 24h log aggregation at most every 15m.
- Read-only credentials. No secrets or raw customer data in snapshots.

## Decisions (user, 2026-11-17)

Two widgets; LogBox first; direct Elastic; URL on the credential account;
environment per widget; all seven hosts hideable; every face selectable;
defaults as above; Small = 15m, medium/large = 24h.

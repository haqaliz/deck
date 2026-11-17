# M11 — verification

**Owner-confirmed on the installed 1.64 build, 2026-11-17.**

## Checked

- Both widgets appear in the Widget Center gallery under Deck.
- **LogBox**: Prod health, What's broken, Single service and Grafana panels
  faces; templates, latest-message and full-line text modes; small/medium/large.
- **MetricBox**: Fleet health (all seven hosts, columns configurable), Single
  host (with 24h CPU trend), Power & cost, Top agents and Alerts; small/medium/
  large.
- Accounts: Elastic (Elasticsearch `:9200` + Kibana URL + key) and Grafana
  (URL + token) both paired and verified with the in-app Verify button.
- Dynamic settings: environments load from `_data_stream/logs-manifold-*`;
  services load from a 24h `service.name` query; hosts load from the Grafana
  snapshot. Re-setting the account fetches first and shows a loading line; no
  cached first paint.
- Unsetting an account: environment/service/host lists clear, the environment,
  service, host and hide-list selections reset, and `logbox.json` /
  `metricbox.json` are deleted.
- Deep links open Kibana Discover and the matching Grafana dashboard with the
  time range (and `var-host` for a single host).
- Failure states: Tailscale offline, wrong key, Grafana 5xx and an empty window
  each show their own message; the last-good snapshot is not presented as
  fresh.
- Privacy: no Elastic or Grafana key value appears in any container JSON.
  LogBox was in templates mode at verification time, with `recent: []` — no
  raw message text on disk.

## Measured

- Elastic: 15m errors by service ~9ms; 24h errors-only trend ~4.4s (cached for
  15 minutes); service catalog ~1.1s (settings only); newest five errors ~17ms.
- Grafana: instant host query plus agents plus alerts ~1–2s; one extra range
  query for the single-host 24h CPU trend.

## Notes

- The first 1.63 install left the old 1.62 process running; `killall Deck` and
  the 1.64 descriptor-cache bump were what refreshed the gallery.
- The owner accepted the current admin-scoped keys for this build. Rotating
  both to read-only remains recommended; the widgets only read.

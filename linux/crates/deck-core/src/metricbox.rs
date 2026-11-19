use std::collections::BTreeMap;

use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use time::OffsetDateTime;

use crate::providers::{self, FetchError};
use crate::settings::{MetricBoxFace, MetricBoxSettings};

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct MetricHost {
    pub host: String,
    pub cpu: Option<f64>,
    pub ram: Option<f64>,
    pub disk: Option<f64>,
    pub last_seen_seconds: Option<f64>,
    pub uptime_seconds: Option<f64>,
    pub gpu_percent: Option<f64>,
    pub vram_percent: Option<f64>,
    pub gpu_temperature: Option<f64>,
    pub cpu_watts: Option<f64>,
    pub gpu_watts: Option<f64>,
    pub kwh_24h: Option<f64>,
}

impl MetricHost {
    fn new(host: &str) -> Self {
        Self {
            host: host.to_owned(),
            cpu: None,
            ram: None,
            disk: None,
            last_seen_seconds: None,
            uptime_seconds: None,
            gpu_percent: None,
            vram_percent: None,
            gpu_temperature: None,
            cpu_watts: None,
            gpu_watts: None,
            kwh_24h: None,
        }
    }

    pub fn total_watts(&self) -> Option<f64> {
        (self.cpu_watts.is_some() || self.gpu_watts.is_some())
            .then(|| self.cpu_watts.unwrap_or(0.0) + self.gpu_watts.unwrap_or(0.0))
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct MetricAgent {
    pub host: String,
    pub name: String,
    pub cpu: Option<f64>,
    pub ram: Option<f64>,
    pub vram: Option<f64>,
    pub gpu: Option<f64>,
}

impl MetricAgent {
    pub fn score(&self) -> f64 {
        self.vram.unwrap_or(0.0) / 1_073_741_824.0
            + self.gpu.unwrap_or(0.0)
            + self.cpu.unwrap_or(0.0) / 100.0
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct MetricAlert {
    pub name: String,
    pub severity: String,
    pub summary: String,
    pub host: String,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct MetricBoxSnapshot {
    pub account_id: String,
    pub hosts: Vec<MetricHost>,
    pub agents: Vec<MetricAgent>,
    pub firing_alerts: Vec<MetricAlert>,
    pub trend_host: Option<String>,
    pub trend_cpu: Vec<f64>,
    pub note: Option<String>,
}

pub const HOST_EXPRESSIONS: [(&str, &str); 11] = [
    ("A", "100 - avg by (host)(rate(node_cpu_seconds_total{mode=\"idle\"}[2m]))*100"),
    ("B", "100*(1 - node_memory_MemAvailable_bytes/node_memory_MemTotal_bytes)"),
    ("C", "100*(1 - node_filesystem_avail_bytes{mountpoint=\"/\"}/node_filesystem_size_bytes{mountpoint=\"/\"})"),
    ("D", "time() - tlast_over_time(up{job=\"node\"}[30d])"),
    ("E", "time() - node_boot_time_seconds"),
    ("F", "max by (host)(nvidia_smi_utilization_gpu_ratio)*100"),
    ("G", "max by (host)(nvidia_smi_memory_used_bytes/nvidia_smi_memory_total_bytes)*100"),
    ("H", "max by (host)(nvidia_smi_temperature_gpu)"),
    ("I", "sum by (host)(rate(node_rapl_package_joules_total[2m]))"),
    ("J", "sum by (host)(nvidia_smi_power_draw_watts)"),
    ("K", "(avg_over_time((sum by (host)(nvidia_smi_power_draw_watts))[24h:5m])*24/1000) + on(host) (sum by (host)(increase(node_rapl_package_joules_total[24h]))/3.6e6)"),
];

pub const AGENT_EXPRESSIONS: [(&str, &str); 4] = [
    ("A", "topk(10, sum by (host, name)(rate(container_cpu_usage_seconds_total{name!=\"\"}[2m]))*100)"),
    ("B", "topk(10, sum by (host, name)(container_memory_working_set_bytes{name!=\"\"}))"),
    ("C", "topk(10, sum by (host, container)(gpu_container_memory_used_bytes))"),
    ("D", "topk(10, sum by (host, container)(gpu_container_sm_utilization_percent))"),
];

pub fn safe_host(raw: &str) -> Option<String> {
    let host = raw.trim();
    if host.is_empty()
        || !host
            .bytes()
            .all(|byte| byte.is_ascii_alphanumeric() || matches!(byte, b'.' | b'_' | b':' | b'-'))
    {
        return None;
    }
    Some(host.to_owned())
}

pub fn single_host_cpu(host: &str) -> Option<String> {
    let host = safe_host(host)?;
    Some(format!(
        "100 - avg by (host)(rate(node_cpu_seconds_total{{mode=\"idle\",host=\"{host}\"}}[2m]))*100"
    ))
}

pub fn query_body(
    uid: &str,
    expressions: &[(&str, &str)],
    from_ms: i64,
    to_ms: i64,
    instant: bool,
    max_points: Option<u32>,
) -> Value {
    let queries: Vec<Value> = expressions
        .iter()
        .map(|(reference, expr)| {
            let mut query = json!({
                "refId": reference,
                "datasource": { "type": "prometheus", "uid": uid },
                "expr": expr,
                "instant": instant,
                "range": !instant
            });
            if let Some(points) = max_points.filter(|_| !instant) {
                query["maxDataPoints"] = json!(points);
                query["intervalMs"] =
                    json!(60_000.max((to_ms - from_ms).max(1) / i64::from(points.max(1))));
            }
            query
        })
        .collect();
    json!({
        "from": from_ms.to_string(),
        "to": to_ms.to_string(),
        "queries": queries
    })
}

#[derive(Debug, Clone, PartialEq)]
pub struct GrafanaSeries {
    pub labels: BTreeMap<String, String>,
    pub values: Vec<f64>,
}

pub fn parse_series(body: &str, ref_id: &str) -> Option<Vec<GrafanaSeries>> {
    let root: Value = serde_json::from_str(body).ok()?;
    let result = root.get("results")?.get(ref_id)?;
    if result.get("status").and_then(Value::as_i64).unwrap_or(200) != 200 {
        return None;
    }
    let frames = result.get("frames")?.as_array()?;
    Some(
        frames
            .iter()
            .filter_map(|frame| {
                let fields = frame.get("schema")?.get("fields")?.as_array()?;
                let value_field = fields
                    .iter()
                    .find(|field| field.get("type").and_then(Value::as_str) == Some("number"))?;
                let columns = frame.get("data")?.get("values")?.as_array()?;
                let values = columns
                    .last()?
                    .as_array()?
                    .iter()
                    .filter_map(Value::as_f64)
                    .collect::<Vec<_>>();
                if values.is_empty() {
                    return None;
                }
                let labels = value_field
                    .get("labels")
                    .and_then(Value::as_object)
                    .map(|map| {
                        map.iter()
                            .filter_map(|(key, value)| {
                                Some((key.clone(), value.as_str()?.to_owned()))
                            })
                            .collect()
                    })
                    .unwrap_or_default();
                Some(GrafanaSeries { labels, values })
            })
            .collect(),
    )
}

pub fn prometheus_uid(body: &str) -> Option<String> {
    let rows = serde_json::from_str::<Vec<Value>>(body).ok()?;
    let prometheus: Vec<&Value> = rows
        .iter()
        .filter(|row| row.get("type").and_then(Value::as_str) == Some("prometheus"))
        .collect();
    let chosen = prometheus
        .iter()
        .find(|row| row.get("isDefault").and_then(Value::as_bool) == Some(true))
        .or_else(|| prometheus.first())?;
    chosen
        .get("uid")
        .and_then(Value::as_str)
        .filter(|uid| !uid.is_empty())
        .map(str::to_owned)
}

pub fn parse_alerts(body: &str) -> Vec<MetricAlert> {
    let Ok(rows) = serde_json::from_str::<Vec<Value>>(body) else {
        return Vec::new();
    };
    rows.iter()
        .filter_map(|row| {
            let labels = row.get("labels")?.as_object()?;
            let name = labels.get("alertname")?.as_str()?;
            if name.is_empty() {
                return None;
            }
            Some(MetricAlert {
                name: name.to_owned(),
                severity: labels
                    .get("severity")
                    .and_then(Value::as_str)
                    .unwrap_or("warning")
                    .to_owned(),
                summary: row
                    .get("annotations")
                    .and_then(|annotations| annotations.get("summary"))
                    .and_then(Value::as_str)
                    .unwrap_or("")
                    .to_owned(),
                host: labels
                    .get("host")
                    .and_then(Value::as_str)
                    .or_else(|| labels.get("instance").and_then(Value::as_str))
                    .unwrap_or("")
                    .to_owned(),
            })
        })
        .collect()
}

pub fn worst_first(hosts: &[MetricHost]) -> Vec<MetricHost> {
    let mut sorted = hosts.to_vec();
    sorted.sort_by(|left, right| {
        let left_silent = left.last_seen_seconds.unwrap_or(0.0) > 120.0;
        let right_silent = right.last_seen_seconds.unwrap_or(0.0) > 120.0;
        if left_silent != right_silent {
            return right_silent.cmp(&left_silent);
        }
        if left_silent {
            return right
                .last_seen_seconds
                .unwrap_or(0.0)
                .partial_cmp(&left.last_seen_seconds.unwrap_or(0.0))
                .unwrap_or(std::cmp::Ordering::Equal);
        }
        let left_pressure = left
            .cpu
            .unwrap_or(0.0)
            .max(left.ram.unwrap_or(0.0))
            .max(left.disk.unwrap_or(0.0));
        let right_pressure = right
            .cpu
            .unwrap_or(0.0)
            .max(right.ram.unwrap_or(0.0))
            .max(right.disk.unwrap_or(0.0));
        right_pressure
            .partial_cmp(&left_pressure)
            .unwrap_or(std::cmp::Ordering::Equal)
            .then_with(|| left.host.cmp(&right.host))
    });
    sorted
}

pub fn fetch(
    base_url: &str,
    token: &str,
    settings: &MetricBoxSettings,
) -> Result<MetricBoxSnapshot, FetchError> {
    let base = providers::normalize_base(base_url).ok_or(FetchError::NotConfigured)?;
    if token.trim().is_empty() {
        return Err(FetchError::NotConfigured);
    }
    let auth = format!("Bearer {token}");
    let datasources = providers::get(
        &format!("{base}/api/datasources"),
        &[("Authorization", &auth), ("Accept", "application/json")],
    )?;
    let uid = prometheus_uid(&datasources).ok_or(FetchError::NotConfigured)?;

    let now = OffsetDateTime::now_utc();
    let to_ms = now.unix_timestamp() * 1000;
    let from_ms = to_ms - 300_000;
    let query = |body: Value| {
        providers::post(
            &format!("{base}/api/ds/query"),
            &[
                ("Authorization", &auth),
                ("Content-Type", "application/json"),
                ("Accept", "application/json"),
            ],
            &body.to_string(),
        )
    };

    let host_data = query(query_body(
        &uid,
        &HOST_EXPRESSIONS,
        from_ms,
        to_ms,
        true,
        None,
    ))?;
    let mut hosts: BTreeMap<String, MetricHost> = BTreeMap::new();
    apply(&mut hosts, &host_data, "A", |host, value| {
        host.cpu = Some(value)
    });
    apply(&mut hosts, &host_data, "B", |host, value| {
        host.ram = Some(value)
    });
    apply(&mut hosts, &host_data, "C", |host, value| {
        host.disk = Some(value)
    });
    apply(&mut hosts, &host_data, "D", |host, value| {
        host.last_seen_seconds = Some(value)
    });
    apply(&mut hosts, &host_data, "E", |host, value| {
        host.uptime_seconds = Some(value)
    });
    apply(&mut hosts, &host_data, "F", |host, value| {
        host.gpu_percent = Some(value)
    });
    apply(&mut hosts, &host_data, "G", |host, value| {
        host.vram_percent = Some(value)
    });
    apply(&mut hosts, &host_data, "H", |host, value| {
        host.gpu_temperature = Some(value)
    });
    apply(&mut hosts, &host_data, "I", |host, value| {
        host.cpu_watts = Some(value)
    });
    apply(&mut hosts, &host_data, "J", |host, value| {
        host.gpu_watts = Some(value)
    });
    apply(&mut hosts, &host_data, "K", |host, value| {
        host.kwh_24h = Some(value)
    });
    if hosts.is_empty() {
        return Err(FetchError::InvalidPayload);
    }

    let mut note = None;
    let agents = match query(query_body(
        &uid,
        &AGENT_EXPRESSIONS,
        from_ms,
        to_ms,
        true,
        None,
    )) {
        Ok(body) => parse_agents(&body),
        Err(_) => {
            note = Some("top agents unavailable".into());
            Vec::new()
        }
    };

    let alerts = providers::get(
        &format!("{base}/api/alertmanager/grafana/api/v2/alerts?active=true"),
        &[("Authorization", &auth), ("Accept", "application/json")],
    )
    .map(|body| parse_alerts(&body))
    .unwrap_or_default();

    let mut trend_host = None;
    let mut trend_cpu = Vec::new();
    if settings.face == MetricBoxFace::Host {
        if let Some(expression) = single_host_cpu(&settings.host) {
            let trend_from = to_ms - i64::from(settings.large_window_minutes) * 60_000;
            if let Ok(body) = query(query_body(
                &uid,
                &[("A", &expression)],
                trend_from,
                to_ms,
                false,
                Some(24),
            )) {
                trend_cpu = parse_series(&body, "A")
                    .and_then(|series| series.first().map(|series| series.values.clone()))
                    .unwrap_or_default();
                trend_host = Some(settings.host.trim().to_owned());
            }
        }
    }

    Ok(MetricBoxSnapshot {
        account_id: "grafana".into(),
        hosts: hosts.into_values().collect(),
        agents,
        firing_alerts: alerts,
        trend_host,
        trend_cpu,
        note,
    })
}

fn apply(
    hosts: &mut BTreeMap<String, MetricHost>,
    body: &str,
    ref_id: &str,
    set: impl Fn(&mut MetricHost, f64),
) {
    for series in parse_series(body, ref_id).unwrap_or_default() {
        let Some(host) = series.labels.get("host").filter(|host| !host.is_empty()) else {
            continue;
        };
        let Some(value) = series.values.last().copied() else {
            continue;
        };
        let entry = hosts
            .entry(host.clone())
            .or_insert_with(|| MetricHost::new(host));
        set(entry, value);
    }
}

fn parse_agents(body: &str) -> Vec<MetricAgent> {
    let mut agents: BTreeMap<String, MetricAgent> = BTreeMap::new();
    {
        let mut apply = |ref_id: &str, set: fn(&mut MetricAgent, f64)| {
            for series in parse_series(body, ref_id).unwrap_or_default() {
                let Some(host) = series.labels.get("host").filter(|host| !host.is_empty()) else {
                    continue;
                };
                let name = series
                    .labels
                    .get("name")
                    .or_else(|| series.labels.get("container"))
                    .filter(|name| !name.is_empty());
                let Some(name) = name else {
                    continue;
                };
                let Some(value) = series.values.last().copied() else {
                    continue;
                };
                let key = format!("{host}/{name}");
                let entry = agents.entry(key).or_insert_with(|| MetricAgent {
                    host: host.clone(),
                    name: name.clone(),
                    cpu: None,
                    ram: None,
                    vram: None,
                    gpu: None,
                });
                set(entry, value);
            }
        };
        apply("A", |agent, value| agent.cpu = Some(value));
        apply("B", |agent, value| agent.ram = Some(value));
        apply("C", |agent, value| agent.vram = Some(value));
        apply("D", |agent, value| agent.gpu = Some(value));
    }
    let mut agents: Vec<MetricAgent> = agents.into_values().collect();
    agents.sort_by(|left, right| {
        right
            .score()
            .partial_cmp(&left.score())
            .unwrap_or(std::cmp::Ordering::Equal)
    });
    agents.truncate(10);
    agents
}

#[cfg(test)]
mod tests {
    use super::*;

    const DATASOURCES: &str = include_str!("../../../contracts/fixtures/grafana_datasources.json");
    const QUERY: &str = include_str!("../../../contracts/fixtures/grafana_query.json");
    const ALERTS: &str = include_str!("../../../contracts/fixtures/grafana_alerts.json");

    #[test]
    fn chooses_the_default_prometheus_datasource() {
        assert_eq!(
            prometheus_uid(DATASOURCES).as_deref(),
            Some("P4169E866C3094E38")
        );
    }

    #[test]
    fn parses_series_labels_and_latest_values() {
        let series = parse_series(QUERY, "A").expect("series");
        assert_eq!(series.len(), 2);
        assert_eq!(
            series[0].labels.get("host").map(String::as_str),
            Some("x201")
        );
        assert_eq!(series[0].values, vec![34.1]);
    }

    #[test]
    fn parses_firing_alerts() {
        let alerts = parse_alerts(ALERTS);
        assert_eq!(alerts.len(), 1);
        assert_eq!(alerts[0].name, "House machine not reporting");
        assert_eq!(alerts[0].host, "x204");
    }

    #[test]
    fn host_labels_are_restricted_to_safe_characters() {
        assert_eq!(safe_host("x201"), Some("x201".into()));
        assert_eq!(safe_host("host-1.example"), Some("host-1.example".into()));
        assert_eq!(safe_host("x\"} or vector(1)"), None);
        assert!(single_host_cpu("x201").unwrap().contains("host=\"x201\""));
    }

    #[test]
    fn query_body_carries_uid_and_instant_flag() {
        let body = query_body("uid", &[("A", "up")], 1_000, 2_000, true, None);
        let text = body.to_string();
        assert!(text.contains("\"uid\":\"uid\""));
        assert!(text.contains("\"instant\":true"));
    }

    #[test]
    fn silent_hosts_sort_first_then_the_busiest() {
        let mut silent = MetricHost::new("silent");
        silent.last_seen_seconds = Some(600.0);
        let mut busy = MetricHost::new("busy");
        busy.cpu = Some(90.0);
        let mut calm = MetricHost::new("calm");
        calm.cpu = Some(10.0);
        let sorted = worst_first(&[calm, busy, silent]);
        assert_eq!(sorted[0].host, "silent");
        assert_eq!(sorted[1].host, "busy");
        assert_eq!(sorted[2].host, "calm");
    }
}

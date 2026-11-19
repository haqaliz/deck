use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use time::format_description::well_known::Rfc3339;
use time::OffsetDateTime;

use crate::providers::{self, FetchError};
use crate::settings::{LogBoxSettings, LogTextMode};

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct LogBoxPoint {
    pub at: String,
    pub count: u64,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct LogBoxCount {
    pub name: String,
    pub count: u64,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct LogBoxLine {
    pub at: String,
    pub service: String,
    pub level: String,
    pub message: String,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct LogBoxSnapshot {
    pub account_id: String,
    pub environment: String,
    pub slow_updated_at: Option<String>,
    pub small_minutes: u16,
    pub large_minutes: u16,
    pub error_small: u64,
    pub warn_small: u64,
    pub error_large: u64,
    pub warn_large: u64,
    pub trend: Vec<LogBoxPoint>,
    pub services: Vec<LogBoxCount>,
    pub templates: Vec<LogBoxCount>,
    pub last_error_at: Option<String>,
    pub recent: Vec<LogBoxLine>,
    pub note: Option<String>,
}

pub fn normalize_environment(raw: &str) -> String {
    let value = raw.trim();
    if value.is_empty() {
        return "logs-manifold-prd".into();
    }
    if value.starts_with("logs-manifold-") {
        value.to_owned()
    } else {
        format!("logs-manifold-{value}")
    }
}

fn valid_index(index: &str) -> bool {
    !index.is_empty()
        && index
            .bytes()
            .all(|byte| byte.is_ascii_alphanumeric() || matches!(byte, b'-' | b'_' | b'.' | b'*'))
}

pub fn search_body(minutes: u16, service: &str, trend_bucket: Option<u16>) -> Value {
    let mut filters = vec![
        json!({ "range": { "@timestamp": { "gte": format!("now-{minutes}m") } } }),
        json!({ "terms": { "log.level": ["error", "critical", "warn"] } }),
    ];
    let service = service.trim();
    if !service.is_empty() {
        filters.push(json!({ "term": { "service.name": service } }));
    }
    let mut error_aggs = json!({
        "services": { "terms": { "field": "service.name", "size": 5 } },
        "templates": { "terms": { "field": "manifold.message_template", "size": 5 } }
    });
    if let Some(bucket) = trend_bucket {
        error_aggs["trend"] = json!({
            "date_histogram": {
                "field": "@timestamp",
                "fixed_interval": format!("{}m", bucket.max(1))
            }
        });
    }
    json!({
        "size": 0,
        "track_total_hits": true,
        "query": { "bool": { "filter": filters } },
        "aggs": {
            "error": {
                "filter": { "terms": { "log.level": ["error", "critical"] } },
                "aggs": error_aggs
            },
            "warn": { "filter": { "term": { "log.level": "warn" } } }
        }
    })
}

pub fn last_error_body(minutes: u16, service: &str) -> Value {
    let mut filters = vec![
        json!({ "range": { "@timestamp": { "gte": format!("now-{minutes}m") } } }),
        json!({ "terms": { "log.level": ["error", "critical"] } }),
    ];
    if !service.trim().is_empty() {
        filters.push(json!({ "term": { "service.name": service.trim() } }));
    }
    json!({
        "size": 5,
        "sort": [{ "@timestamp": "desc" }],
        "query": { "bool": { "filter": filters } },
        "_source": ["@timestamp", "message", "manifold.message_template", "service", "log"]
    })
}

pub fn trend_bucket_minutes(minutes: u16) -> u16 {
    (minutes / 48).max(5)
}

#[derive(Debug, Clone, PartialEq, Default)]
pub struct Counts {
    pub error: u64,
    pub warn: u64,
    pub services: Vec<LogBoxCount>,
    pub templates: Vec<LogBoxCount>,
    pub trend: Vec<LogBoxPoint>,
}

pub fn parse_counts(body: &str) -> Option<Counts> {
    let root: Value = serde_json::from_str(body).ok()?;
    let aggs = root.get("aggregations")?;
    let error = aggs.get("error")?;
    Some(Counts {
        error: error.get("doc_count").and_then(Value::as_u64).unwrap_or(0),
        warn: aggs
            .get("warn")
            .and_then(|warn| warn.get("doc_count"))
            .and_then(Value::as_u64)
            .unwrap_or(0),
        services: buckets(error.get("services")),
        templates: buckets(error.get("templates")),
        trend: trend_buckets(error.get("trend")),
    })
}

pub fn parse_recent(body: &str) -> Vec<LogBoxLine> {
    let Ok(root) = serde_json::from_str::<Value>(body) else {
        return Vec::new();
    };
    let Some(hits) = root
        .get("hits")
        .and_then(|hits| hits.get("hits"))
        .and_then(Value::as_array)
    else {
        return Vec::new();
    };
    hits.iter()
        .filter_map(|hit| {
            let source = hit.get("_source")?;
            Some(LogBoxLine {
                at: source.get("@timestamp")?.as_str()?.to_owned(),
                service: source
                    .get("service")
                    .and_then(|service| service.get("name"))
                    .and_then(Value::as_str)
                    .unwrap_or("")
                    .to_owned(),
                level: source
                    .get("log")
                    .and_then(|log| log.get("level"))
                    .and_then(Value::as_str)
                    .unwrap_or("")
                    .to_owned(),
                message: source
                    .get("message")
                    .and_then(Value::as_str)
                    .or_else(|| {
                        source
                            .get("manifold")
                            .and_then(|manifold| manifold.get("message_template"))
                            .and_then(Value::as_str)
                    })
                    .unwrap_or("")
                    .to_owned(),
            })
        })
        .collect()
}

pub fn parse_service_names(body: &str) -> Option<Vec<String>> {
    let root: Value = serde_json::from_str(body).ok()?;
    let buckets = root
        .get("aggregations")?
        .get("services")?
        .get("buckets")?
        .as_array()?;
    Some(
        buckets
            .iter()
            .filter_map(|bucket| bucket.get("key").and_then(Value::as_str).map(str::to_owned))
            .collect(),
    )
}

pub fn parse_environments(body: &str) -> Option<Vec<String>> {
    let root: Value = serde_json::from_str(body).ok()?;
    let streams = root.get("data_streams")?.as_array()?;
    Some(
        streams
            .iter()
            .filter_map(|stream| stream.get("name").and_then(Value::as_str))
            .filter(|name| name.starts_with("logs-manifold-"))
            .map(str::to_owned)
            .collect(),
    )
}

fn buckets(value: Option<&Value>) -> Vec<LogBoxCount> {
    value
        .and_then(|agg| agg.get("buckets"))
        .and_then(Value::as_array)
        .map(|rows| {
            rows.iter()
                .filter_map(|row| {
                    Some(LogBoxCount {
                        name: row.get("key")?.as_str()?.to_owned(),
                        count: row.get("doc_count").and_then(Value::as_u64).unwrap_or(0),
                    })
                })
                .collect()
        })
        .unwrap_or_default()
}

fn trend_buckets(value: Option<&Value>) -> Vec<LogBoxPoint> {
    value
        .and_then(|agg| agg.get("buckets"))
        .and_then(Value::as_array)
        .map(|rows| {
            rows.iter()
                .filter_map(|row| {
                    Some(LogBoxPoint {
                        at: row.get("key_as_string")?.as_str()?.to_owned(),
                        count: row.get("doc_count").and_then(Value::as_u64).unwrap_or(0),
                    })
                })
                .collect()
        })
        .unwrap_or_default()
}

fn parse_time(value: &str) -> Option<OffsetDateTime> {
    OffsetDateTime::parse(value, &Rfc3339).ok()
}

pub fn fetch(
    base_url: &str,
    api_key: &str,
    settings: &LogBoxSettings,
    previous: Option<&LogBoxSnapshot>,
) -> Result<LogBoxSnapshot, FetchError> {
    let base = providers::normalize_base(base_url).ok_or(FetchError::NotConfigured)?;
    if api_key.trim().is_empty() {
        return Err(FetchError::NotConfigured);
    }
    let index = normalize_environment(&settings.environment);
    if !valid_index(&index) {
        return Err(FetchError::NotConfigured);
    }
    let url = format!("{base}/{index}/_search");
    let auth = format!("ApiKey {api_key}");
    let post = |body: &Value| {
        providers::post(
            &url,
            &[
                ("Authorization", &auth),
                ("Content-Type", "application/json"),
                ("Accept", "application/json"),
            ],
            &body.to_string(),
        )
    };

    let fast = parse_counts(&post(&search_body(
        settings.small_minutes,
        &settings.service,
        None,
    ))?)
    .ok_or(FetchError::InvalidPayload)?;

    let now = OffsetDateTime::now_utc();
    let same_target = previous
        .map(|snapshot| snapshot.environment == index)
        .unwrap_or(false);
    let slow_fresh = same_target
        && previous
            .and_then(|snapshot| snapshot.slow_updated_at.as_deref())
            .and_then(parse_time)
            .map(|at| (now - at).whole_seconds() < 15 * 60)
            .unwrap_or(false);

    let mut slow_updated_at = previous
        .filter(|_| slow_fresh)
        .and_then(|snapshot| snapshot.slow_updated_at.clone());
    let mut error_large = previous
        .filter(|_| slow_fresh)
        .map(|s| s.error_large)
        .unwrap_or(0);
    let mut warn_large = previous
        .filter(|_| slow_fresh)
        .map(|s| s.warn_large)
        .unwrap_or(0);
    let mut trend = previous
        .filter(|_| slow_fresh)
        .map(|snapshot| snapshot.trend.clone())
        .unwrap_or_default();
    let mut services = previous
        .filter(|_| slow_fresh)
        .map(|snapshot| snapshot.services.clone())
        .unwrap_or_default();
    let mut templates = previous
        .filter(|_| slow_fresh)
        .map(|snapshot| snapshot.templates.clone())
        .unwrap_or_default();
    let mut note = None;

    if !slow_fresh {
        let slow = post(&search_body(
            settings.large_minutes,
            &settings.service,
            Some(trend_bucket_minutes(settings.large_minutes)),
        ))
        .and_then(|body| parse_counts(&body).ok_or(FetchError::InvalidPayload));
        match slow {
            Ok(slow) => {
                slow_updated_at = Some(now.format(&Rfc3339).unwrap_or_default());
                error_large = slow.error;
                warn_large = slow.warn;
                trend = slow.trend;
                services = slow.services;
                templates = slow.templates;
            }
            Err(_) => {
                if previous.is_none() || !same_target {
                    note = Some("24h trend unavailable".into());
                }
            }
        }
    }

    let recent = if settings.text_mode == LogTextMode::Templates {
        Vec::new()
    } else {
        match post(&last_error_body(settings.large_minutes, &settings.service))
            .ok()
            .map(|body| parse_recent(&body))
        {
            Some(lines) => lines,
            None => previous
                .filter(|_| same_target)
                .map(|snapshot| snapshot.recent.clone())
                .unwrap_or_default(),
        }
    };

    Ok(LogBoxSnapshot {
        account_id: "elastic".into(),
        environment: index,
        slow_updated_at,
        small_minutes: settings.small_minutes,
        large_minutes: settings.large_minutes,
        error_small: fast.error,
        warn_small: fast.warn,
        error_large,
        warn_large,
        trend,
        services,
        templates,
        last_error_at: recent.first().map(|line| line.at.clone()),
        recent,
        note,
    })
}

pub fn environment_catalog(base_url: &str, api_key: &str) -> Result<Vec<String>, FetchError> {
    let base = providers::normalize_base(base_url).ok_or(FetchError::NotConfigured)?;
    let body = providers::get(
        &format!("{base}/_data_stream/logs-manifold-*"),
        &[
            ("Authorization", &format!("ApiKey {api_key}")),
            ("Accept", "application/json"),
        ],
    )?;
    let mut names = parse_environments(&body).ok_or(FetchError::InvalidPayload)?;
    names.sort();
    Ok(names)
}

pub fn service_catalog(
    base_url: &str,
    api_key: &str,
    environment: &str,
) -> Result<Vec<String>, FetchError> {
    let base = providers::normalize_base(base_url).ok_or(FetchError::NotConfigured)?;
    let index = normalize_environment(environment);
    if !valid_index(&index) {
        return Err(FetchError::NotConfigured);
    }
    let body = json!({
        "size": 0,
        "query": { "range": { "@timestamp": { "gte": "now-24h" } } },
        "aggs": { "services": { "terms": { "field": "service.name", "size": 50 } } }
    });
    let response = providers::post(
        &format!("{base}/{index}/_search"),
        &[
            ("Authorization", &format!("ApiKey {api_key}")),
            ("Content-Type", "application/json"),
        ],
        &body.to_string(),
    )?;
    let mut names = parse_service_names(&response).ok_or(FetchError::InvalidPayload)?;
    names.sort();
    Ok(names)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::settings::LogTextMode;

    const COUNTS: &str = r#"{
      "aggregations": {
        "error": {
          "doc_count": 4,
          "services": {"buckets": [{"key": "api", "doc_count": 3}, {"key": "web", "doc_count": 1}]},
          "templates": {"buckets": [{"key": "timeout %s", "doc_count": 2}]},
          "trend": {"buckets": [
            {"key_as_string": "2026-11-19T09:00:00.000Z", "doc_count": 1},
            {"key_as_string": "2026-11-19T10:00:00.000Z", "doc_count": 3}
          ]}
        },
        "warn": {"doc_count": 7}
      }
    }"#;

    const RECENT: &str = r#"{"hits":{"hits":[
      {"_source":{"@timestamp":"2026-11-19T10:00:00Z","service":{"name":"api"},"log":{"level":"error"},"message":"boom"}},
      {"_source":{"@timestamp":"2026-11-19T09:00:00Z","service":{"name":"web"},"log":{"level":"critical"},"manifold":{"message_template":"timeout %s"}}}
    ]}}"#;

    #[test]
    fn normalizes_environments_and_rejects_bad_indices() {
        assert_eq!(normalize_environment("prd"), "logs-manifold-prd");
        assert_eq!(normalize_environment("stg"), "logs-manifold-stg");
        assert_eq!(
            normalize_environment("logs-manifold-prd"),
            "logs-manifold-prd"
        );
        assert!(valid_index("logs-manifold-prd"));
        assert!(!valid_index("../secret"));
    }

    #[test]
    fn query_bodies_carry_the_window_and_service() {
        let body = search_body(15, "api", Some(5));
        let text = body.to_string();
        assert!(text.contains("now-15m"));
        assert!(text.contains("\"service.name\":\"api\""));
        assert!(text.contains("\"fixed_interval\":\"5m\""));
        assert_eq!(trend_bucket_minutes(1440), 30);
    }

    #[test]
    fn parses_counts_services_templates_and_trend() {
        let counts = parse_counts(COUNTS).expect("counts");
        assert_eq!(counts.error, 4);
        assert_eq!(counts.warn, 7);
        assert_eq!(counts.services[0].name, "api");
        assert_eq!(counts.services[0].count, 3);
        assert_eq!(counts.templates[0].name, "timeout %s");
        assert_eq!(counts.trend.len(), 2);
        assert_eq!(counts.trend[1].count, 3);
    }

    #[test]
    fn parses_recent_lines_from_message_or_template() {
        let recent = parse_recent(RECENT);
        assert_eq!(recent.len(), 2);
        assert_eq!(recent[0].message, "boom");
        assert_eq!(recent[0].service, "api");
        assert_eq!(recent[1].message, "timeout %s");
        assert_eq!(recent[1].level, "critical");
    }

    #[test]
    fn parsers_tolerate_unknown_payloads() {
        assert!(parse_counts("{}").is_none());
        assert!(parse_recent("{}").is_empty());
        assert!(parse_environments("{}").is_none());
        assert_eq!(LogTextMode::Templates, LogTextMode::default());
    }
}

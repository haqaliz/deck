use std::path::{Path, PathBuf};

use rusqlite::{Connection, OpenFlags};
use serde::{Deserialize, Serialize};

use crate::error::CoreError;
use crate::providers::{self, FetchError};

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct OpenCodeSnapshot {
    /// Sessions started in the last 24 hours.
    pub sessions: i64,
    /// Tokens for those sessions.
    pub input: i64,
    pub output: i64,
    pub cost: f64,
    /// Last 14 calendar days, oldest first.
    pub daily: Vec<Day>,
    pub models: Vec<Model>,
    pub tools: Vec<ToolCount>,
    pub session_list: Vec<SessionRow>,
    pub total_input: i64,
    pub total_output: i64,
    pub total_cost: f64,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Day {
    pub day: String,
    pub input: i64,
    pub output: i64,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Model {
    pub model: String,
    pub cost: f64,
    pub input: i64,
    pub output: i64,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ToolCount {
    pub tool: String,
    pub count: i64,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SessionRow {
    pub title: String,
    pub input: i64,
    pub output: i64,
    pub time_created: i64,
}

pub fn default_db_path() -> PathBuf {
    if let Some(data) = std::env::var_os("XDG_DATA_HOME") {
        return PathBuf::from(data).join("opencode/opencode.db");
    }
    let home = std::env::var_os("HOME").unwrap_or_default();
    PathBuf::from(home).join(".local/share/opencode/opencode.db")
}

#[derive(Debug, Deserialize)]
struct RemoteSession {
    id: String,
    #[serde(default)]
    title: String,
    time: RemoteTime,
    cost: Option<f64>,
    tokens: Option<RemoteTokens>,
    model: Option<RemoteModel>,
}

#[derive(Debug, Deserialize)]
struct RemoteTime {
    created: f64,
    updated: f64,
}

#[derive(Debug, Deserialize)]
struct RemoteTokens {
    input: f64,
    output: f64,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct RemoteModel {
    id: String,
}

/// Reads an `opencode serve` instance. Only servers with session-level usage
/// are supported; older servers need per-message aggregation and return an
/// unreadable payload rather than a misleading empty face.
pub fn load_remote(server_url: &str, token: &str) -> Result<OpenCodeSnapshot, FetchError> {
    let base = providers::normalize_base(server_url).ok_or(FetchError::NotConfigured)?;
    if token.trim().is_empty() {
        return Err(FetchError::NotConfigured);
    }
    let auth = providers::basic_auth("opencode", token);
    let body = providers::get(
        &format!("{base}/session"),
        &[("Authorization", &auth), ("Accept", "application/json")],
    )?;
    let sessions: Vec<RemoteSession> =
        serde_json::from_str(&body).map_err(|_| FetchError::InvalidPayload)?;
    aggregate_remote(&sessions, now_millis()).ok_or(FetchError::InvalidPayload)
}

fn now_millis() -> f64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|duration| duration.as_millis() as f64)
        .unwrap_or(0.0)
}

fn aggregate_remote(sessions: &[RemoteSession], now: f64) -> Option<OpenCodeSnapshot> {
    if !sessions
        .iter()
        .any(|session| session.cost.is_some() || session.tokens.is_some())
    {
        return None;
    }
    let cutoff = now - 14.0 * 86_400_000.0;
    let day_cutoff = now - 86_400_000.0;
    let mut daily: std::collections::BTreeMap<String, (i64, i64)> =
        std::collections::BTreeMap::new();
    let mut models: std::collections::BTreeMap<String, Model> = std::collections::BTreeMap::new();
    let mut total_input = 0;
    let mut total_output = 0;
    let mut total_cost = 0.0;
    let mut recent_sessions = 0;
    let mut recent_input = 0;
    let mut recent_output = 0;
    let mut recent_cost = 0.0;

    for session in sessions
        .iter()
        .filter(|session| session.time.created >= cutoff)
    {
        let tokens = session.tokens.as_ref();
        let input = tokens.map(|tokens| tokens.input as i64).unwrap_or(0);
        let output = tokens.map(|tokens| tokens.output as i64).unwrap_or(0);
        let cost = session.cost.unwrap_or(0.0);
        total_input += input;
        total_output += output;
        total_cost += cost;
        if session.time.created >= day_cutoff {
            recent_sessions += 1;
            recent_input += input;
            recent_output += output;
            recent_cost += cost;
        }
        if let Some(day) = chrono::DateTime::from_timestamp_millis(session.time.created as i64)
            .map(|at| at.format("%Y-%m-%d").to_string())
        {
            let entry = daily.entry(day).or_insert((0, 0));
            entry.0 += input;
            entry.1 += output;
        }
        let model = session
            .model
            .as_ref()
            .map(|model| model.id.clone())
            .unwrap_or_else(|| "unknown".into());
        let entry = models.entry(model.clone()).or_insert_with(|| Model {
            model,
            cost: 0.0,
            input: 0,
            output: 0,
        });
        entry.cost += cost;
        entry.input += input;
        entry.output += output;
    }

    let mut session_list: Vec<SessionRow> = sessions
        .iter()
        .filter(|session| session.time.created >= cutoff)
        .map(|session| SessionRow {
            title: if session.title.is_empty() {
                session.id.clone()
            } else {
                session.title.clone()
            },
            input: session
                .tokens
                .as_ref()
                .map(|tokens| tokens.input as i64)
                .unwrap_or(0),
            output: session
                .tokens
                .as_ref()
                .map(|tokens| tokens.output as i64)
                .unwrap_or(0),
            time_created: session.time.updated as i64,
        })
        .collect();
    session_list.sort_by(|left, right| right.time_created.cmp(&left.time_created));
    session_list.truncate(10);

    let mut models: Vec<Model> = models.into_values().collect();
    models.sort_by(|left, right| right.cost.total_cmp(&left.cost));

    Some(OpenCodeSnapshot {
        sessions: recent_sessions,
        input: recent_input,
        output: recent_output,
        cost: recent_cost,
        daily: daily
            .into_iter()
            .map(|(day, (input, output))| Day { day, input, output })
            .collect(),
        models,
        tools: Vec::new(),
        session_list,
        total_input,
        total_output,
        total_cost,
    })
}

/// `Ok(None)` when opencode is not installed; errors are real read failures.
pub fn load() -> Result<Option<OpenCodeSnapshot>, CoreError> {
    load_from(&default_db_path())
}

pub fn load_from(path: &Path) -> Result<Option<OpenCodeSnapshot>, CoreError> {
    if !path.is_file() {
        return Ok(None);
    }
    let conn = Connection::open_with_flags(path, OpenFlags::SQLITE_OPEN_READ_ONLY)?;
    conn.busy_timeout(std::time::Duration::from_secs(2))?;
    snapshot(&conn).map(Some)
}

fn snapshot(conn: &Connection) -> Result<OpenCodeSnapshot, CoreError> {
    let (sessions, input, output, cost) = conn.query_row(
        "SELECT COUNT(*), COALESCE(SUM(tokens_input), 0), COALESCE(SUM(tokens_output), 0),
                COALESCE(ROUND(SUM(cost), 4), 0)
         FROM session
         WHERE time_created > (strftime('%s','now') * 1000 - 86400000)",
        [],
        |row| {
            Ok((
                row.get::<_, i64>(0)?,
                row.get::<_, i64>(1)?,
                row.get::<_, i64>(2)?,
                row.get::<_, f64>(3)?,
            ))
        },
    )?;

    let mut daily = Vec::new();
    let mut statement = conn.prepare(
        "SELECT date(time_created / 1000, 'unixepoch') as day,
                COALESCE(SUM(tokens_input), 0), COALESCE(SUM(tokens_output), 0)
         FROM session
         WHERE time_created > (strftime('%s','now','-13 days') * 1000)
         GROUP BY day ORDER BY day",
    )?;
    let rows = statement.query_map([], |row| {
        Ok(Day {
            day: row.get(0)?,
            input: row.get(1)?,
            output: row.get(2)?,
        })
    })?;
    for row in rows {
        daily.push(row?);
    }

    let mut models = Vec::new();
    let mut statement = conn.prepare(
        "SELECT model, COALESCE(ROUND(SUM(cost), 4), 0),
                COALESCE(SUM(tokens_input), 0), COALESCE(SUM(tokens_output), 0)
         FROM session WHERE model IS NOT NULL
         GROUP BY model ORDER BY SUM(cost) DESC LIMIT 3",
    )?;
    let rows = statement.query_map([], |row| {
        Ok(Model {
            model: row.get(0)?,
            cost: row.get(1)?,
            input: row.get(2)?,
            output: row.get(3)?,
        })
    })?;
    for row in rows {
        models.push(row?);
    }

    let mut tools = Vec::new();
    let mut statement = conn.prepare(
        "SELECT json_extract(data, '$.tool') as tool, COUNT(*) as count
         FROM part WHERE json_extract(data, '$.type') = 'tool'
         GROUP BY tool ORDER BY count DESC LIMIT 10",
    )?;
    let rows = statement.query_map([], |row| {
        Ok(ToolCount {
            tool: row.get(0)?,
            count: row.get(1)?,
        })
    })?;
    for row in rows {
        tools.push(row?);
    }
    tools.sort_by(|left, right| {
        right
            .count
            .cmp(&left.count)
            .then_with(|| left.tool.cmp(&right.tool))
    });

    let mut session_list = Vec::new();
    let mut statement = conn.prepare(
        "SELECT title, COALESCE(tokens_input, 0), COALESCE(tokens_output, 0), time_created
         FROM session
         WHERE time_created > (strftime('%s','now','-13 days') * 1000)
           AND title IS NOT NULL
         ORDER BY (COALESCE(tokens_input, 0) + COALESCE(tokens_output, 0)) DESC
         LIMIT 10",
    )?;
    let rows = statement.query_map([], |row| {
        Ok(SessionRow {
            title: row.get(0)?,
            input: row.get(1)?,
            output: row.get(2)?,
            time_created: row.get(3)?,
        })
    })?;
    for row in rows {
        session_list.push(row?);
    }

    let (total_input, total_output, total_cost) = conn.query_row(
        "SELECT COALESCE(SUM(tokens_input), 0), COALESCE(SUM(tokens_output), 0),
                COALESCE(ROUND(SUM(cost), 4), 0) FROM session",
        [],
        |row| {
            Ok((
                row.get::<_, i64>(0)?,
                row.get::<_, i64>(1)?,
                row.get::<_, f64>(2)?,
            ))
        },
    )?;

    Ok(OpenCodeSnapshot {
        sessions,
        input,
        output,
        cost,
        daily,
        models,
        tools,
        session_list,
        total_input,
        total_output,
        total_cost,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn fixture() -> Connection {
        let conn = Connection::open_in_memory().expect("memory");
        conn.execute_batch(
            "CREATE TABLE session (
                title TEXT, model TEXT, tokens_input INTEGER, tokens_output INTEGER,
                cost REAL, time_created INTEGER
             );
             CREATE TABLE part (data TEXT);",
        )
        .expect("schema");
        let now = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .expect("clock")
            .as_millis() as i64;
        conn.execute(
            "INSERT INTO session VALUES ('Build the port', 'claude', 1000, 500, 0.25, ?1)",
            [now],
        )
        .expect("session");
        conn.execute(
            "INSERT INTO session VALUES ('Old work', 'gpt', 4000, 100, 1.5, ?1)",
            [now - 10 * 86_400_000],
        )
        .expect("session");
        conn.execute(
            "INSERT INTO part VALUES ('{\"type\":\"tool\",\"tool\":\"bash\"}')",
            [],
        )
        .expect("part");
        conn.execute(
            "INSERT INTO part VALUES ('{\"type\":\"tool\",\"tool\":\"bash\"}')",
            [],
        )
        .expect("part");
        conn.execute(
            "INSERT INTO part VALUES ('{\"type\":\"tool\",\"tool\":\"read\"}')",
            [],
        )
        .expect("part");
        conn
    }

    #[test]
    fn reads_today_totals_models_tools_and_sessions() {
        let snapshot = snapshot(&fixture()).expect("snapshot");
        assert_eq!(snapshot.sessions, 1);
        assert_eq!(snapshot.input, 1000);
        assert_eq!(snapshot.output, 500);
        assert_eq!(snapshot.cost, 0.25);
        assert_eq!(snapshot.total_input, 5000);
        assert_eq!(snapshot.total_cost, 1.75);
        assert_eq!(snapshot.tools[0].tool, "bash");
        assert_eq!(snapshot.tools[0].count, 2);
        assert_eq!(snapshot.session_list[0].title, "Old work");
    }

    #[test]
    fn a_missing_database_is_not_an_error() {
        assert!(load_from(Path::new("/nonexistent/opencode.db"))
            .expect("load")
            .is_none());
    }
}

#[cfg(test)]
mod remote_tests {
    use super::{aggregate_remote, RemoteSession};

    #[test]
    fn aggregates_session_level_usage() {
        let body = r#"[
          {"id":"a","title":"Deck work","time":{"created":1700000000000,"updated":1700000100000},
           "cost":1.5,"tokens":{"input":1000,"output":200,"cache":{"read":0,"write":0}},
           "model":{"id":"gpt-5"}},
          {"id":"b","title":"Other","time":{"created":1700000000000,"updated":1700000050000},
           "cost":0.5,"tokens":{"input":500,"output":100,"cache":{"read":0,"write":0}},
           "model":{"id":"gpt-5"}}
        ]"#;
        let sessions: Vec<RemoteSession> = serde_json::from_str(body).expect("sessions");
        let snapshot = aggregate_remote(&sessions, 1700000200000.0).expect("snapshot");
        assert_eq!(snapshot.total_input, 1500);
        assert_eq!(snapshot.total_output, 300);
        assert_eq!(snapshot.models[0].model, "gpt-5");
        assert_eq!(snapshot.session_list.len(), 2);
        let no_usage: Vec<RemoteSession> =
            serde_json::from_str(r#"[{"id":"x","time":{"created":0,"updated":0}}]"#)
                .expect("sessions");
        assert!(aggregate_remote(&no_usage, 1.0).is_none());
    }
}

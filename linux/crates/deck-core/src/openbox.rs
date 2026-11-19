use std::path::{Path, PathBuf};

use rusqlite::{Connection, OpenFlags};
use serde::{Deserialize, Serialize};

use crate::error::CoreError;

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

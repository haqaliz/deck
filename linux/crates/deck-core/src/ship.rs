use serde::{Deserialize, Serialize};
use serde_json::Value;

use crate::providers::{self, FetchError};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum ShipStatus {
    Queued,
    Running,
    Success,
    Failure,
    Neutral,
}

impl ShipStatus {
    pub fn map(status: &str, conclusion: Option<&str>) -> Self {
        match (status, conclusion) {
            ("queued" | "waiting" | "requested" | "pending", _) => Self::Queued,
            ("in_progress", _) => Self::Running,
            ("completed", Some("success")) => Self::Success,
            ("completed", Some("failure" | "timed_out" | "action_required" | "stale")) => {
                Self::Failure
            }
            _ => Self::Neutral,
        }
    }

    pub fn label(self) -> &'static str {
        match self {
            Self::Queued => "QUEUED",
            Self::Running => "RUNNING",
            Self::Success => "PASS",
            Self::Failure => "FAIL",
            Self::Neutral => "—",
        }
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ShipRun {
    pub repo: String,
    pub name: String,
    pub run_number: i64,
    pub branch: String,
    pub status: ShipStatus,
    pub created_at: String,
    pub updated_at: String,
    pub html_url: String,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ShipBoxSnapshot {
    pub repos: Vec<String>,
    pub runs: Vec<ShipRun>,
    pub note: Option<String>,
}

pub fn parse_runs(body: &str) -> Option<Vec<ShipRun>> {
    let json: Value = serde_json::from_str(body).ok()?;
    let runs = json.get("workflow_runs")?.as_array()?;
    Some(
        runs.iter()
            .filter_map(|run| {
                Some(ShipRun {
                    repo: String::new(),
                    name: run.get("name")?.as_str()?.to_owned(),
                    run_number: run.get("run_number").and_then(Value::as_i64).unwrap_or(0),
                    branch: run
                        .get("head_branch")
                        .and_then(Value::as_str)
                        .unwrap_or("")
                        .to_owned(),
                    status: ShipStatus::map(
                        run.get("status").and_then(Value::as_str).unwrap_or(""),
                        run.get("conclusion").and_then(Value::as_str),
                    ),
                    created_at: run
                        .get("created_at")
                        .and_then(Value::as_str)
                        .unwrap_or("")
                        .to_owned(),
                    updated_at: run
                        .get("updated_at")
                        .and_then(Value::as_str)
                        .unwrap_or("")
                        .to_owned(),
                    html_url: run
                        .get("html_url")
                        .and_then(Value::as_str)
                        .unwrap_or("")
                        .to_owned(),
                })
            })
            .collect(),
    )
}

pub fn fetch(
    repos: &[String],
    per_page: usize,
    token: &str,
) -> Result<ShipBoxSnapshot, FetchError> {
    if repos.is_empty() {
        return Err(FetchError::NotConfigured);
    }
    if token.trim().is_empty() {
        return Err(FetchError::NotConfigured);
    }
    let per_page = per_page.clamp(2, 8);
    let mut all = Vec::new();
    let mut failures = Vec::new();
    let mut first_error = None;
    for repo in repos {
        let repo = repo.trim().trim_matches('/');
        if !valid_repo(repo) {
            failures.push(format!("{repo}: invalid repo"));
            continue;
        }
        let url = format!("https://api.github.com/repos/{repo}/actions/runs?per_page={per_page}");
        match providers::get(
            &url,
            &[
                ("Authorization", &format!("Bearer {token}")),
                ("Accept", "application/vnd.github+json"),
                ("X-GitHub-Api-Version", "2022-11-28"),
            ],
        ) {
            Ok(body) => match parse_runs(&body) {
                Some(runs) => all.extend(runs.into_iter().map(|run| ShipRun {
                    repo: repo.to_owned(),
                    ..run
                })),
                None => {
                    failures.push(format!("{repo}: unreadable"));
                    first_error.get_or_insert(FetchError::InvalidPayload);
                }
            },
            Err(error) => {
                failures.push(format!("{repo}: {}", error.message()));
                first_error.get_or_insert(error);
            }
        }
    }
    if all.is_empty() {
        if let Some(error) = first_error {
            return Err(error);
        }
    }
    all.sort_by(|left, right| {
        right
            .created_at
            .cmp(&left.created_at)
            .then_with(|| left.repo.cmp(&right.repo))
    });
    Ok(ShipBoxSnapshot {
        repos: repos.to_vec(),
        runs: all,
        note: (!failures.is_empty()).then(|| failures.join(" · ")),
    })
}

fn valid_repo(repo: &str) -> bool {
    let mut parts = repo.split('/');
    let owner = parts.next().unwrap_or("");
    let name = parts.next().unwrap_or("");
    parts.next().is_none()
        && !owner.is_empty()
        && !name.is_empty()
        && repo
            .bytes()
            .all(|byte| byte.is_ascii_alphanumeric() || matches!(byte, b'-' | b'_' | b'.' | b'/'))
}

#[derive(Debug, Default, PartialEq, Eq)]
pub struct ShipTotals {
    pub success: usize,
    pub failure: usize,
    pub running: usize,
    pub queued: usize,
    pub neutral: usize,
}

pub fn totals(runs: &[ShipRun]) -> ShipTotals {
    let mut totals = ShipTotals::default();
    for run in runs {
        match run.status {
            ShipStatus::Success => totals.success += 1,
            ShipStatus::Failure => totals.failure += 1,
            ShipStatus::Running => totals.running += 1,
            ShipStatus::Queued => totals.queued += 1,
            ShipStatus::Neutral => totals.neutral += 1,
        }
    }
    totals
}

pub fn totals_line(runs: &[ShipRun]) -> String {
    let totals = totals(runs);
    let mut parts = Vec::new();
    if totals.failure > 0 {
        parts.push(format!("{} fail", totals.failure));
    }
    if totals.success > 0 {
        parts.push(format!("{} pass", totals.success));
    }
    if totals.running > 0 {
        parts.push(format!("{} run", totals.running));
    }
    if totals.queued > 0 {
        parts.push(format!("{} queued", totals.queued));
    }
    parts.join(" · ")
}

#[cfg(test)]
mod tests {
    use super::*;

    const FIXTURE: &str = include_str!("../../../contracts/fixtures/github_actions_runs.json");

    #[test]
    fn parses_runs_and_status_pairs() {
        let runs = parse_runs(FIXTURE).expect("runs");
        assert_eq!(runs.len(), 3);
        assert_eq!(runs[0].name, "CI");
        assert_eq!(runs[0].run_number, 42);
        assert_eq!(runs[0].status, ShipStatus::Success);
        assert_eq!(runs[1].status, ShipStatus::Failure);
        assert_eq!(runs[2].status, ShipStatus::Running);
        assert_eq!(
            ShipStatus::map("completed", Some("cancelled")),
            ShipStatus::Neutral
        );
    }

    #[test]
    fn totals_line_names_only_non_zero_states() {
        let runs = parse_runs(FIXTURE).expect("runs");
        assert_eq!(totals_line(&runs), "1 fail · 1 pass · 1 run");
        assert_eq!(totals(&runs).success, 1);
    }

    #[test]
    fn repo_validation_requires_owner_and_name() {
        assert!(valid_repo("haqaliz/deck"));
        assert!(!valid_repo("deck"));
        assert!(!valid_repo("owner/name/extra"));
        assert!(!valid_repo("owner/na me"));
    }
}

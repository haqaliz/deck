use serde::{Deserialize, Serialize};
use serde_json::{json, Value};

use crate::providers::{self, FetchError};

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct TaskItem {
    pub id: String,
    pub title: String,
    pub state: String,
    pub item_type: String,
    pub url: String,
    pub changed_at: Option<String>,
    pub project: Option<String>,
    pub organization: Option<String>,
    pub tags: Vec<String>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct TaskBoxSnapshot {
    pub scope: String,
    pub total_count: usize,
    pub sprint: Option<String>,
    pub tasks: Vec<TaskItem>,
    pub note: Option<String>,
    pub total_is_lower_bound: bool,
    pub is_custom_query: bool,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum TaskLane {
    Todo,
    InProgress,
    Testing,
    Done,
    Other,
}

impl TaskLane {
    pub fn label(self) -> &'static str {
        match self {
            Self::Todo => "TO DO",
            Self::InProgress => "IN PROGRESS",
            Self::Testing => "TESTING",
            Self::Done => "DONE",
            Self::Other => "OTHER",
        }
    }
}

/// Case-insensitive match against the default Azure process vocabulary.
pub fn lane(state: &str) -> TaskLane {
    let state = state.trim().to_lowercase();
    const DONE: &[&str] = &["done", "closed", "resolved", "completed", "removed"];
    const TODO: &[&str] = &["new", "approved", "to do", "open", "proposed"];
    const PROGRESS: &[&str] = &["committed", "in progress", "doing", "active", "started"];
    const TESTING: &[&str] = &["testing", "in test", "qa", "in review", "review"];
    if DONE.contains(&state.as_str()) {
        TaskLane::Done
    } else if TODO.contains(&state.as_str()) {
        TaskLane::Todo
    } else if PROGRESS.contains(&state.as_str()) {
        TaskLane::InProgress
    } else if TESTING.contains(&state.as_str()) {
        TaskLane::Testing
    } else {
        TaskLane::Other
    }
}

pub fn parse_work_items(body: &str, organization: &str, project: &str) -> Option<Vec<TaskItem>> {
    let json: Value = serde_json::from_str(body).ok()?;
    let items = json.get("value")?.as_array()?;
    Some(
        items
            .iter()
            .filter_map(|item| {
                let fields = item.get("fields")?;
                let id = item.get("id")?.as_i64()?.to_string();
                let tags = fields
                    .get("System.Tags")
                    .and_then(Value::as_str)
                    .unwrap_or("")
                    .split(';')
                    .map(str::trim)
                    .filter(|tag| !tag.is_empty())
                    .map(str::to_owned)
                    .collect();
                Some(TaskItem {
                    id,
                    title: field_text(fields, "System.Title"),
                    state: field_text(fields, "System.State"),
                    item_type: field_text(fields, "System.WorkItemType"),
                    url: item
                        .get("_links")
                        .and_then(|links| links.get("html"))
                        .and_then(|html| html.get("href"))
                        .and_then(Value::as_str)
                        .unwrap_or("")
                        .to_owned(),
                    changed_at: fields
                        .get("System.ChangedDate")
                        .and_then(Value::as_str)
                        .map(str::to_owned),
                    project: (!project.is_empty()).then(|| project.to_owned()),
                    organization: (!organization.is_empty()).then(|| organization.to_owned()),
                    tags,
                })
            })
            .collect(),
    )
}

fn field_text(fields: &Value, key: &str) -> String {
    fields
        .get(key)
        .and_then(Value::as_str)
        .unwrap_or("")
        .to_owned()
}

pub fn fetch(
    organization: &str,
    project: &str,
    token: &str,
    query: &str,
    limit: usize,
) -> Result<TaskBoxSnapshot, FetchError> {
    let organization = normalize_org(organization);
    let project = project.trim();
    if organization.is_empty() || project.is_empty() {
        return Err(FetchError::NotConfigured);
    }
    if token.trim().is_empty() {
        return Err(FetchError::NotConfigured);
    }
    let auth = providers::basic_auth("", token);
    let wiql = if query.trim().is_empty() {
        "SELECT [System.Id] FROM WorkItems \
         WHERE [System.AssignedTo] = @Me \
         AND [System.State] <> 'Done' AND [System.State] <> 'Closed' \
         AND [System.State] <> 'Removed' \
         ORDER BY [System.ChangedDate] DESC"
    } else {
        query.trim()
    };
    let base = format!(
        "https://dev.azure.com/{organization}/{}",
        providers::encode_path(project)
    );
    let url = format!("{base}/_apis/wit/wiql?api-version=7.0&$top={limit}");
    let body = json!({ "query": wiql }).to_string();
    let response = providers::post(
        &url,
        &[
            ("Authorization", &auth),
            ("Content-Type", "application/json"),
            ("Accept", "application/json"),
        ],
        &body,
    )?;
    let ids = parse_wiql_ids(&response).ok_or(FetchError::InvalidPayload)?;
    if ids.is_empty() {
        return Ok(TaskBoxSnapshot {
            scope: project.to_owned(),
            total_count: 0,
            sprint: None,
            tasks: Vec::new(),
            note: None,
            total_is_lower_bound: false,
            is_custom_query: !query.trim().is_empty(),
        });
    }
    let ids_param = ids.iter().map(i64::to_string).collect::<Vec<_>>().join(",");
    let items_url =
        format!("{base}/_apis/wit/workitems?ids={ids_param}&$expand=all&api-version=7.0");
    let items = providers::get(
        &items_url,
        &[("Authorization", &auth), ("Accept", "application/json")],
    )?;
    let mut tasks =
        parse_work_items(&items, &organization, project).ok_or(FetchError::InvalidPayload)?;
    tasks.sort_by(|left, right| {
        right
            .changed_at
            .cmp(&left.changed_at)
            .then_with(|| left.id.cmp(&right.id))
    });
    Ok(TaskBoxSnapshot {
        scope: project.to_owned(),
        total_count: tasks.len(),
        sprint: None,
        tasks,
        note: None,
        total_is_lower_bound: ids.len() >= limit,
        is_custom_query: !query.trim().is_empty(),
    })
}

fn normalize_org(raw: &str) -> String {
    raw.trim()
        .trim_end_matches('/')
        .trim_start_matches("https://")
        .trim_start_matches("http://")
        .trim_start_matches("dev.azure.com/")
        .to_owned()
}

pub fn parse_wiql_ids(body: &str) -> Option<Vec<i64>> {
    let json: Value = serde_json::from_str(body).ok()?;
    let items = json.get("workItems")?.as_array()?;
    Some(
        items
            .iter()
            .filter_map(|item| item.get("id").and_then(Value::as_i64))
            .collect(),
    )
}

pub fn lane_counts(tasks: &[TaskItem]) -> [(TaskLane, usize); 5] {
    let mut counts = [
        (TaskLane::Todo, 0),
        (TaskLane::InProgress, 0),
        (TaskLane::Testing, 0),
        (TaskLane::Done, 0),
        (TaskLane::Other, 0),
    ];
    for task in tasks {
        let task_lane = lane(&task.state);
        if let Some(entry) = counts.iter_mut().find(|(lane, _)| *lane == task_lane) {
            entry.1 += 1;
        }
    }
    counts
}

#[cfg(test)]
mod tests {
    use super::*;

    const FIXTURE: &str = include_str!("../../../contracts/fixtures/azure_workitems.json");

    #[test]
    fn parses_work_items_and_fields() {
        let tasks = parse_work_items(FIXTURE, "acme", "Manifold").expect("tasks");
        assert_eq!(tasks.len(), 2);
        assert_eq!(tasks[0].id, "101");
        assert_eq!(tasks[0].title, "Fix the flux capacitor");
        assert_eq!(tasks[0].state, "Active");
        assert_eq!(tasks[0].item_type, "Bug");
        assert_eq!(tasks[0].tags, vec!["backend", "urgent"]);
        assert_eq!(tasks[0].project.as_deref(), Some("Manifold"));
        assert!(tasks[0].url.starts_with("https://dev.azure.com/"));
    }

    #[test]
    fn maps_states_to_lanes_case_insensitively() {
        assert_eq!(lane("Active"), TaskLane::InProgress);
        assert_eq!(lane("Done"), TaskLane::Done);
        assert_eq!(lane("In Review"), TaskLane::Testing);
        assert_eq!(lane("To Do"), TaskLane::Todo);
        assert_eq!(lane("Something"), TaskLane::Other);
        assert_eq!(lane(""), TaskLane::Other);
    }

    #[test]
    fn parses_wiql_ids() {
        let ids = parse_wiql_ids(r#"{"workItems":[{"id":1},{"id":2}]}"#).expect("ids");
        assert_eq!(ids, vec![1, 2]);
    }

    #[test]
    fn org_normalization_accepts_a_url_or_a_name() {
        assert_eq!(normalize_org("acme"), "acme");
        assert_eq!(normalize_org("https://dev.azure.com/acme/"), "acme");
    }
}

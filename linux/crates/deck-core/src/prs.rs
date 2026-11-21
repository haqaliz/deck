use serde::{Deserialize, Serialize};
use serde_json::Value;

use crate::providers::{self, FetchError};

#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum PrProvider {
    Github,
    AzureDevOps,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum PrRole {
    Authored,
    Reviewing,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum PrReviewState {
    Approved,
    ChangesRequested,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct PullRequestItem {
    pub id: String,
    pub number: i64,
    pub title: String,
    pub repo: String,
    pub role: PrRole,
    pub provider: PrProvider,
    pub is_draft: bool,
    pub created_at: String,
    pub url: String,
    pub project: Option<String>,
    pub organization: Option<String>,
    /// "owner/name" for GitHub; needed for the per-PR review lookup.
    pub full_repo: Option<String>,
    pub review_state: Option<PrReviewState>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct PrBoxSnapshot {
    pub authored_count: usize,
    pub reviewing_count: usize,
    pub authored_capped: bool,
    pub reviewing_capped: bool,
    pub pull_requests: Vec<PullRequestItem>,
    pub note: Option<String>,
}

pub struct PrSources<'a> {
    pub github_token: Option<&'a str>,
    pub azure_token: Option<&'a str>,
    pub azure_org: &'a str,
    pub azure_project: &'a str,
    pub limit: usize,
    pub show_review_state: bool,
}

pub fn parse_github(body: &str, role: PrRole) -> Option<(usize, Vec<PullRequestItem>)> {
    let json: Value = serde_json::from_str(body).ok()?;
    let total = json.get("total_count").and_then(Value::as_u64).unwrap_or(0) as usize;
    let items = json.get("items")?.as_array()?;
    let rows = items
        .iter()
        .filter(|item| item.get("pull_request").is_some())
        .filter_map(|item| {
            let repo_url = item.get("repository_url")?.as_str()?;
            let repo = repo_from_api_url(repo_url)?;
            let number = item.get("number")?.as_i64()?;
            Some(PullRequestItem {
                id: format!("github:{repo}#{number}"),
                number,
                title: item.get("title")?.as_str()?.to_owned(),
                repo: repo.rsplit('/').next().unwrap_or(&repo).to_owned(),
                role,
                provider: PrProvider::Github,
                is_draft: item.get("draft").and_then(Value::as_bool).unwrap_or(false),
                created_at: item
                    .get("created_at")
                    .and_then(Value::as_str)
                    .unwrap_or("")
                    .to_owned(),
                url: item
                    .get("html_url")
                    .and_then(Value::as_str)
                    .unwrap_or("")
                    .to_owned(),
                project: None,
                organization: None,
                review_state: None,
                full_repo: Some(repo),
            })
        })
        .collect();
    Some((total, rows))
}

pub fn parse_azure(
    body: &str,
    role: PrRole,
    organization: &str,
    project: &str,
) -> Option<Vec<PullRequestItem>> {
    let json: Value = serde_json::from_str(body).ok()?;
    let items = json.get("value")?.as_array()?;
    Some(
        items
            .iter()
            .filter_map(|item| {
                let number = item.get("pullRequestId")?.as_i64()?;
                let repo = item
                    .get("repository")
                    .and_then(|repository| repository.get("name"))
                    .and_then(Value::as_str)?;
                let url = format!(
                    "https://dev.azure.com/{organization}/{project}/_git/{repo}/pullrequest/{number}"
                );
                Some(PullRequestItem {
                    id: format!("azure:{organization}:{project}:{repo}#{number}"),
                    number,
                    title: item.get("title")?.as_str()?.to_owned(),
                    repo: repo.to_owned(),
                    role,
                    provider: PrProvider::AzureDevOps,
                    is_draft: item.get("isDraft").and_then(Value::as_bool).unwrap_or(false),
                    created_at: item
                        .get("creationDate")
                        .and_then(Value::as_str)
                        .unwrap_or("")
                        .to_owned(),
                    url,
                    project: Some(project.to_owned()),
                    organization: Some(organization.to_owned()),
                    full_repo: None,
                    review_state: azure_review_state(item),
                })
            })
            .collect(),
    )
}

fn azure_review_state(item: &Value) -> Option<PrReviewState> {
    let reviewers = item.get("reviewers")?.as_array()?;
    let mut approved = false;
    for reviewer in reviewers {
        match reviewer.get("vote").and_then(Value::as_i64).unwrap_or(0) {
            -10 | -5 => return Some(PrReviewState::ChangesRequested),
            10 | 5 => approved = true,
            _ => {}
        }
    }
    approved.then_some(PrReviewState::Approved)
}

fn github_review_state(token: &str, full_repo: &str, number: i64) -> Option<PrReviewState> {
    let url =
        format!("https://api.github.com/repos/{full_repo}/pulls/{number}/reviews?per_page=100");
    let body = providers::get(
        &url,
        &[
            ("Authorization", &format!("Bearer {token}")),
            ("Accept", "application/vnd.github+json"),
            ("X-GitHub-Api-Version", "2022-11-28"),
        ],
    )
    .ok()?;
    let json: Value = serde_json::from_str(&body).ok()?;
    let mut latest: Option<(String, PrReviewState)> = None;
    for review in json.as_array()? {
        let state = match review.get("state").and_then(Value::as_str) {
            Some("APPROVED") => PrReviewState::Approved,
            Some("CHANGES_REQUESTED") => PrReviewState::ChangesRequested,
            _ => continue,
        };
        let at = review
            .get("submitted_at")
            .and_then(Value::as_str)
            .unwrap_or("")
            .to_owned();
        if latest
            .as_ref()
            .map(|(latest, _)| at > *latest)
            .unwrap_or(true)
        {
            latest = Some((at, state));
        }
    }
    latest.map(|(_, state)| state)
}

fn repo_from_api_url(url: &str) -> Option<String> {
    let parts: Vec<&str> = url.trim_end_matches('/').split('/').collect();
    let name = parts.last()?;
    let owner = parts.get(parts.len().checked_sub(2)?)?;
    Some(format!("{owner}/{name}"))
}

pub fn dedupe(rows: Vec<PullRequestItem>) -> Vec<PullRequestItem> {
    let mut seen = std::collections::HashMap::new();
    let mut out: Vec<PullRequestItem> = Vec::new();
    for row in rows {
        let key = (row.provider, row.number, row.repo.clone());
        if let Some(index) = seen.get(&key).copied() {
            if row.role == PrRole::Authored {
                out[index] = row;
            }
        } else {
            seen.insert(key, out.len());
            out.push(row);
        }
    }
    out
}

pub fn sort(rows: &mut [PullRequestItem]) {
    rows.sort_by(|left, right| {
        right
            .created_at
            .cmp(&left.created_at)
            .then_with(|| left.id.cmp(&right.id))
    });
}

pub fn fetch(sources: PrSources) -> Result<PrBoxSnapshot, FetchError> {
    let limit = sources.limit.clamp(3, 12);
    let mut rows = Vec::new();
    let mut notes = Vec::new();
    let mut errors = 0;
    let mut attempts = 0;

    if let Some(token) = sources
        .github_token
        .filter(|token| !token.trim().is_empty())
    {
        for (role, query) in [
            (PrRole::Authored, "author:@me"),
            (PrRole::Reviewing, "review-requested:@me"),
        ] {
            attempts += 1;
            let url = format!(
                "https://api.github.com/search/issues?q=is:pr+is:open+{query}&sort=created&order=desc&per_page={limit}"
            );
            match providers::get(
                &url,
                &[
                    ("Authorization", &format!("Bearer {token}")),
                    ("Accept", "application/vnd.github+json"),
                    ("X-GitHub-Api-Version", "2022-11-28"),
                ],
            ) {
                Ok(body) => match parse_github(&body, role) {
                    Some((_, mut parsed)) => rows.append(&mut parsed),
                    None => {
                        errors += 1;
                        notes.push("GitHub: unreadable".into());
                    }
                },
                Err(error) => {
                    errors += 1;
                    notes.push(format!("GitHub: {}", error.message()));
                }
            }
        }
    }

    let organization = normalize_org(sources.azure_org);
    let project = sources.azure_project.trim();
    if let Some(token) = sources.azure_token.filter(|token| !token.trim().is_empty()) {
        if organization.is_empty() || project.is_empty() {
            notes.push("Azure: organization and project required".into());
        } else {
            let auth = providers::basic_auth("", token);
            match azure_user_id(&organization, &auth) {
                Err(error) => {
                    errors += 1;
                    notes.push(format!("Azure: {}", error.message()));
                }
                Ok(user_id) => {
                    for (role, criterion) in [
                        (PrRole::Authored, "creatorId"),
                        (PrRole::Reviewing, "reviewerId"),
                    ] {
                        attempts += 1;
                        let url = format!(
                            "https://dev.azure.com/{organization}/{}/_apis/git/pullrequests?searchCriteria.status=active&searchCriteria.{criterion}={user_id}&$top={limit}&api-version=7.0",
                            providers::encode_path(project)
                        );
                        match providers::get(
                            &url,
                            &[("Authorization", &auth), ("Accept", "application/json")],
                        ) {
                            Ok(body) => match parse_azure(&body, role, &organization, project) {
                                Some(mut parsed) => rows.append(&mut parsed),
                                None => {
                                    errors += 1;
                                    notes.push("Azure: unreadable".into());
                                }
                            },
                            Err(error) => {
                                errors += 1;
                                notes.push(format!("Azure: {}", error.message()));
                            }
                        }
                    }
                }
            }
        }
    }

    if attempts == 0 {
        return Err(FetchError::NotConfigured);
    }
    if rows.is_empty() && errors > 0 {
        return Err(FetchError::AuthOrTarget);
    }

    if sources.show_review_state {
        if let Some(token) = sources
            .github_token
            .filter(|token| !token.trim().is_empty())
        {
            for row in rows
                .iter_mut()
                .filter(|row| row.provider == PrProvider::Github && row.review_state.is_none())
            {
                if let Some(repo) = row.full_repo.clone() {
                    row.review_state = github_review_state(token, &repo, row.number);
                }
            }
        }
    }
    let mut rows = dedupe(rows);
    sort(&mut rows);
    let authored_count = rows
        .iter()
        .filter(|row| row.role == PrRole::Authored)
        .count();
    let reviewing_count = rows
        .iter()
        .filter(|row| row.role == PrRole::Reviewing)
        .count();
    Ok(PrBoxSnapshot {
        authored_count,
        reviewing_count,
        authored_capped: authored_count >= limit,
        reviewing_capped: reviewing_count >= limit,
        pull_requests: rows,
        note: (!notes.is_empty()).then(|| notes.join(" · ")),
    })
}

fn azure_user_id(organization: &str, auth: &str) -> Result<String, FetchError> {
    let body = providers::get(
        &format!("https://dev.azure.com/{organization}/_apis/connectionData?api-version=7.0"),
        &[("Authorization", auth), ("Accept", "application/json")],
    )?;
    let json: Value = serde_json::from_str(&body).map_err(|_| FetchError::InvalidPayload)?;
    json.get("authenticatedUser")
        .and_then(|user| user.get("id"))
        .and_then(Value::as_str)
        .map(str::to_owned)
        .ok_or(FetchError::InvalidPayload)
}

fn normalize_org(raw: &str) -> String {
    raw.trim()
        .trim_end_matches('/')
        .trim_start_matches("https://")
        .trim_start_matches("http://")
        .trim_start_matches("dev.azure.com/")
        .to_owned()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_github_search_rows() {
        let body = include_str!("../../../contracts/fixtures/github_prs.json");
        let (total, rows) = parse_github(body, PrRole::Authored).expect("github");
        assert!(total >= 3);
        assert_eq!(rows.len(), 3);
        assert_eq!(rows[0].number, 1);
        assert_eq!(rows[0].repo, "dev");
        assert_eq!(rows[0].id, "github:haqaliz/dev#1");
        assert_eq!(rows[0].provider, PrProvider::Github);
    }

    #[test]
    fn parses_azure_rows_and_builds_the_web_url() {
        let body = include_str!("../../../contracts/fixtures/azure_prs.json");
        let rows = parse_azure(body, PrRole::Reviewing, "acme", "Manifold").expect("azure");
        assert!(!rows.is_empty());
        assert_eq!(rows[0].number, 4475);
        assert_eq!(rows[0].repo, "manifold-validation-swa");
        assert_eq!(rows[0].organization.as_deref(), Some("acme"));
        assert!(rows[0].url.ends_with("/pullrequest/4475"));
        assert_eq!(rows[0].provider, PrProvider::AzureDevOps);
    }

    #[test]
    fn authored_wins_when_the_same_pr_arrives_twice() {
        let body = include_str!("../../../contracts/fixtures/github_prs.json");
        let (_, authored) = parse_github(body, PrRole::Authored).expect("authored");
        let (_, reviewing) = parse_github(body, PrRole::Reviewing).expect("reviewing");
        let mut rows = authored;
        rows.extend(reviewing);
        let rows = dedupe(rows);
        assert!(rows.iter().all(|row| row.role == PrRole::Authored));
        assert_eq!(rows.len(), 3);
    }

    #[test]
    fn azure_review_votes_become_a_state() {
        let rejected = serde_json::json!({"reviewers":[{"vote":10},{"vote":-10}]});
        assert_eq!(
            azure_review_state(&rejected),
            Some(PrReviewState::ChangesRequested)
        );
        let approved = serde_json::json!({"reviewers":[{"vote":10}]});
        assert_eq!(azure_review_state(&approved), Some(PrReviewState::Approved));
        let waiting = serde_json::json!({"reviewers":[{"vote":-5}]});
        assert_eq!(
            azure_review_state(&waiting),
            Some(PrReviewState::ChangesRequested)
        );
        let none = serde_json::json!({"reviewers":[{"vote":0}]});
        assert_eq!(azure_review_state(&none), None);
    }

    #[test]
    fn org_normalization_accepts_a_url_or_a_name() {
        assert_eq!(normalize_org("acme"), "acme");
        assert_eq!(normalize_org("https://dev.azure.com/acme/"), "acme");
    }
}

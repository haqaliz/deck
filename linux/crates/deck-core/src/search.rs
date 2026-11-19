use chrono::{DateTime, Utc};

use crate::clockbox::{self, Zone};
use crate::devbox::{DockerContainer, ListeningPort};
use crate::gitbox::GitBoxSnapshot;
use crate::livebox::ProcessSample;
use crate::logbox::LogBoxSnapshot;
use crate::market::MarketSnapshot;
use crate::metricbox::MetricBoxSnapshot;
use crate::openbox::OpenCodeSnapshot;
use crate::prs::PrBoxSnapshot;
use crate::ship::{ShipBoxSnapshot, ShipStatus};
use crate::tasks::TaskBoxSnapshot;
use crate::weather::WeatherSnapshot;

#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord)]
pub enum SearchProvider {
    Port,
    Time,
    OpenCode,
    Run,
    System,
    Network,
    Git,
    Weather,
    Task,
    Pr,
    Log,
    Metric,
    Market,
}

impl SearchProvider {
    pub fn prefix(self) -> &'static str {
        match self {
            Self::Port => "port",
            Self::Time => "time",
            Self::OpenCode => "oc",
            Self::Run => "run",
            Self::System => "sys",
            Self::Network => "net",
            Self::Git => "git",
            Self::Weather => "weather",
            Self::Task => "task",
            Self::Pr => "pr",
            Self::Log => "log",
            Self::Metric => "metric",
            Self::Market => "mkt",
        }
    }

    pub fn title(self) -> &'static str {
        match self {
            Self::Port => "Dev",
            Self::Time => "Clocks",
            Self::OpenCode => "OpenCode sessions",
            Self::Run => "Builds",
            Self::System => "System",
            Self::Network => "Network",
            Self::Git => "Git",
            Self::Weather => "Weather",
            Self::Task => "Work items",
            Self::Pr => "Pull requests",
            Self::Log => "Logs",
            Self::Metric => "Metrics",
            Self::Market => "Markets",
        }
    }

    fn from_prefix(prefix: &str) -> Option<Self> {
        Some(match prefix {
            "port" => Self::Port,
            "time" => Self::Time,
            "oc" => Self::OpenCode,
            "run" => Self::Run,
            "sys" => Self::System,
            "net" => Self::Network,
            "git" => Self::Git,
            "weather" => Self::Weather,
            "wi" | "task" | "bug" | "pbi" | "backlog" | "story" | "epic" | "feature" => Self::Task,
            "pr" => Self::Pr,
            "log" => Self::Log,
            "metric" => Self::Metric,
            "mkt" => Self::Market,
            _ => return None,
        })
    }

    /// `pr` and `mkt` cost network calls on macOS; Linux reads snapshots, but
    /// the prefix rule stays so the two platforms behave the same.
    fn requires_prefix(self) -> bool {
        matches!(self, Self::Pr | Self::Market)
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum WorkItemKind {
    Any,
    Bug,
    Backlog,
    Epic,
    Feature,
    Task,
}

impl WorkItemKind {
    fn from_prefix(prefix: &str) -> Option<Self> {
        Some(match prefix {
            "wi" => Self::Any,
            "bug" => Self::Bug,
            "pbi" | "backlog" | "story" => Self::Backlog,
            "epic" => Self::Epic,
            "feature" => Self::Feature,
            "task" => Self::Task,
            _ => return None,
        })
    }

    fn matches(self, item_type: &str) -> bool {
        let item_type = item_type.to_lowercase();
        match self {
            Self::Any => true,
            Self::Bug => item_type.contains("bug"),
            Self::Backlog => {
                item_type.contains("product backlog")
                    || item_type.contains("user story")
                    || item_type.contains("requirement")
            }
            Self::Epic => item_type.contains("epic"),
            Self::Feature => item_type.contains("feature"),
            Self::Task => item_type.contains("task"),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SearchQuery {
    pub scope: Option<SearchProvider>,
    pub text: String,
    pub work_item_kind: Option<WorkItemKind>,
}

impl SearchQuery {
    pub fn is_empty(&self) -> bool {
        self.text.trim().is_empty()
    }
}

/// A prefix scopes only as the first token **and only once followed by
/// whitespace**, so typing "port" while meaning "portfolio" still searches
/// every source.
pub fn parse(raw: &str) -> SearchQuery {
    let leading = raw.trim_start();
    if let Some(split) = leading.find(char::is_whitespace) {
        let token = leading[..split].to_lowercase();
        let rest = leading[split..].trim().to_owned();
        if let Some(kind) = WorkItemKind::from_prefix(&token) {
            return SearchQuery {
                scope: Some(SearchProvider::Task),
                text: rest,
                work_item_kind: Some(kind),
            };
        }
        if let Some(scope) = SearchProvider::from_prefix(&token) {
            return SearchQuery {
                scope: Some(scope),
                text: rest,
                work_item_kind: None,
            };
        }
    }
    SearchQuery {
        scope: None,
        text: leading.trim().to_owned(),
        work_item_kind: None,
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum SearchAction {
    Copy(String),
    Open(String),
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SearchResult {
    pub id: String,
    pub provider: SearchProvider,
    pub title: String,
    pub subtitle: String,
    pub score: i32,
    pub action: SearchAction,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SearchSection {
    pub provider: SearchProvider,
    pub results: Vec<SearchResult>,
}

#[derive(Debug, Clone, Default)]
pub struct SearchInputs {
    pub weather: Option<WeatherSnapshot>,
    pub git: Option<GitBoxSnapshot>,
    pub market: Option<MarketSnapshot>,
    pub opencode: Option<OpenCodeSnapshot>,
    pub ship: Option<ShipBoxSnapshot>,
    pub tasks: Option<TaskBoxSnapshot>,
    pub prs: Option<PrBoxSnapshot>,
    pub logbox: Option<LogBoxSnapshot>,
    pub metricbox: Option<MetricBoxSnapshot>,
    pub clock_ids: Vec<String>,
    pub processes: Vec<ProcessSample>,
    pub interfaces: Vec<String>,
    pub ports: Vec<ListeningPort>,
    pub containers: Vec<DockerContainer>,
}

pub fn score(query: &str, candidate: &str) -> Option<i32> {
    let query = query.trim().to_lowercase();
    let candidate = candidate.to_lowercase();
    let tokens: Vec<&str> = query.split_whitespace().collect();
    if tokens.is_empty() {
        return None;
    }
    let words: Vec<&str> = candidate.split_whitespace().collect();
    let mut total = 0;
    for token in tokens {
        if candidate == token {
            total += 300;
        } else if candidate.starts_with(token) {
            total += 200;
        } else if words.iter().any(|word| word.starts_with(token)) {
            total += 100;
        } else if candidate.contains(token) {
            total += 50;
        } else {
            return None;
        }
    }
    Some(total)
}

fn best_score(query: &str, candidates: &[&str]) -> Option<i32> {
    candidates
        .iter()
        .filter_map(|candidate| score(query, candidate))
        .max()
}

pub fn run(inputs: &SearchInputs, raw: &str, now: DateTime<Utc>) -> Vec<SearchSection> {
    let query = parse(raw);
    if query.is_empty() {
        return Vec::new();
    }
    set_current_query(&query.text);
    let mut results = Vec::new();
    for provider in [
        SearchProvider::Port,
        SearchProvider::Time,
        SearchProvider::OpenCode,
        SearchProvider::Run,
        SearchProvider::System,
        SearchProvider::Network,
        SearchProvider::Git,
        SearchProvider::Weather,
        SearchProvider::Task,
        SearchProvider::Pr,
        SearchProvider::Log,
        SearchProvider::Metric,
        SearchProvider::Market,
    ] {
        if let Some(scope) = query.scope {
            if scope != provider {
                continue;
            }
        } else if provider.requires_prefix() {
            continue;
        }
        results.extend(match provider {
            SearchProvider::Port => dev(inputs),
            SearchProvider::Time => clocks(inputs, now),
            SearchProvider::OpenCode => opencode(inputs),
            SearchProvider::Run => runs(inputs),
            SearchProvider::System => system(inputs),
            SearchProvider::Network => network(inputs),
            SearchProvider::Git => git(inputs),
            SearchProvider::Weather => weather(inputs),
            SearchProvider::Task => tasks(inputs, query.work_item_kind),
            SearchProvider::Pr => prs(inputs),
            SearchProvider::Log => logs(inputs),
            SearchProvider::Metric => metrics(inputs),
            SearchProvider::Market => market(inputs),
        });
    }
    let limit = if query.scope.is_some() { 10 } else { 5 };
    group(results, limit)
}

fn group(results: Vec<SearchResult>, limit: usize) -> Vec<SearchSection> {
    let mut sections = Vec::new();
    for provider in [
        SearchProvider::Port,
        SearchProvider::Time,
        SearchProvider::OpenCode,
        SearchProvider::Run,
        SearchProvider::System,
        SearchProvider::Network,
        SearchProvider::Git,
        SearchProvider::Weather,
        SearchProvider::Task,
        SearchProvider::Pr,
        SearchProvider::Log,
        SearchProvider::Metric,
        SearchProvider::Market,
    ] {
        let mut mine: Vec<SearchResult> = results
            .iter()
            .filter(|result| result.provider == provider)
            .cloned()
            .collect();
        mine.sort_by(|left, right| {
            right
                .score
                .cmp(&left.score)
                .then_with(|| left.title.cmp(&right.title))
                .then_with(|| left.id.cmp(&right.id))
        });
        mine.truncate(limit);
        if !mine.is_empty() {
            sections.push(SearchSection {
                provider,
                results: mine,
            });
        }
    }
    sections
}

fn dev(inputs: &SearchInputs) -> Vec<SearchResult> {
    let mut out = Vec::new();
    for port in &inputs.ports {
        let haystack = format!("{} {} tcp", port.port, port.protocol);
        if best_score(&current_query(), &[&haystack]).is_none() {
            continue;
        }
        out.push(SearchResult {
            id: format!("port:{}:{}", port.protocol, port.port),
            provider: SearchProvider::Port,
            title: format!("{} :{}", port.protocol, port.port),
            subtitle: "Listening port".into(),
            score: best_score(&current_query(), &[&haystack]).unwrap_or(0),
            action: SearchAction::Copy(port.port.to_string()),
        });
    }
    for container in &inputs.containers {
        let haystack = format!(
            "{} {} {}",
            container.name, container.image, container.status
        );
        let Some(score) = best_score(&current_query(), &[&haystack]) else {
            continue;
        };
        out.push(SearchResult {
            id: format!("container:{}", container.name),
            provider: SearchProvider::Port,
            title: container.name.clone(),
            subtitle: format!("{} · {}", container.image, container.status),
            score,
            action: SearchAction::Copy(container.name.clone()),
        });
    }
    out
}

// The provider functions receive the query through this thread-local to keep
// their signatures small; `run` sets it once and every matcher reads it.
thread_local! {
    static CURRENT_QUERY: std::cell::RefCell<String> = const { std::cell::RefCell::new(String::new()) };
}

fn current_query() -> String {
    CURRENT_QUERY.with(|query| query.borrow().clone())
}

fn set_current_query(query: &str) {
    CURRENT_QUERY.with(|current| *current.borrow_mut() = query.to_owned());
}

fn clocks(inputs: &SearchInputs, now: DateTime<Utc>) -> Vec<SearchResult> {
    let mut ids: Vec<&str> = clockbox::CURATED_CITIES.to_vec();
    for id in &inputs.clock_ids {
        if !ids.contains(&id.as_str()) {
            ids.push(id);
        }
    }
    let query = current_query();
    ids.iter()
        .filter_map(|id| {
            let zone = clockbox::resolve(id)?;
            let name = clockbox::display_name(id);
            let score = best_score(&query, &[&name, id])?;
            let time = clockbox::time_label(zone, now);
            let day = clockbox::relative_day(zone, Zone::Local, now);
            let offset = clockbox::offset_label(zone, Zone::Local, now);
            Some(SearchResult {
                id: format!("time:{id}"),
                provider: SearchProvider::Time,
                title: name,
                subtitle: format!("{time} · {day} · {offset}"),
                score,
                action: SearchAction::Copy(time),
            })
        })
        .collect()
}

fn opencode(inputs: &SearchInputs) -> Vec<SearchResult> {
    let Some(snapshot) = &inputs.opencode else {
        return Vec::new();
    };
    let query = current_query();
    snapshot
        .session_list
        .iter()
        .enumerate()
        .filter_map(|(index, session)| {
            let score = best_score(&query, &[&session.title])?;
            Some(SearchResult {
                id: format!("oc:{index}:{}", session.title),
                provider: SearchProvider::OpenCode,
                title: session.title.clone(),
                subtitle: format!("{} tokens", session.input + session.output),
                score,
                action: SearchAction::Copy(session.title.clone()),
            })
        })
        .collect()
}

fn runs(inputs: &SearchInputs) -> Vec<SearchResult> {
    let Some(snapshot) = &inputs.ship else {
        return Vec::new();
    };
    let query = current_query();
    snapshot
        .runs
        .iter()
        .filter_map(|run| {
            let haystack = format!(
                "{} {} {} #{} {}",
                run.name, run.branch, run.repo, run.run_number, run.run_number
            );
            let mut score = best_score(&query, &[&haystack])?;
            if query.trim() == run.run_number.to_string()
                || query.trim() == format!("#{}", run.run_number)
            {
                score += 1000;
            }
            let action = web_url(&run.html_url)
                .map(SearchAction::Open)
                .unwrap_or_else(|| SearchAction::Copy(format!("#{}", run.run_number)));
            Some(SearchResult {
                id: format!("run:{}:{}:{}", run.repo, run.name, run.run_number),
                provider: SearchProvider::Run,
                title: format!("{} #{}", run.name, run.run_number),
                subtitle: [
                    run.repo.as_str(),
                    run.branch.as_str(),
                    status_word(run.status),
                ]
                .into_iter()
                .filter(|part| !part.is_empty())
                .collect::<Vec<_>>()
                .join(" · "),
                score,
                action,
            })
        })
        .collect()
}

fn system(inputs: &SearchInputs) -> Vec<SearchResult> {
    let query = current_query();
    inputs
        .processes
        .iter()
        .filter_map(|process| {
            let pid = process.pid.to_string();
            let score = best_score(&query, &[&process.name, &pid])?;
            Some(SearchResult {
                id: format!("sys:{}", process.pid),
                provider: SearchProvider::System,
                title: format!("{} ({})", process.name, process.pid),
                subtitle: format!(
                    "{:.0}% · {:.0} MB",
                    process.cpu_percent,
                    process.rss_bytes as f64 / 1_048_576.0
                ),
                score,
                action: SearchAction::Copy(pid),
            })
        })
        .collect()
}

fn network(inputs: &SearchInputs) -> Vec<SearchResult> {
    let query = current_query();
    inputs
        .interfaces
        .iter()
        .filter_map(|interface| {
            let score = best_score(&query, &[interface])?;
            Some(SearchResult {
                id: format!("net:{interface}"),
                provider: SearchProvider::Network,
                title: interface.clone(),
                subtitle: "Network interface".into(),
                score,
                action: SearchAction::Copy(interface.clone()),
            })
        })
        .collect()
}

fn git(inputs: &SearchInputs) -> Vec<SearchResult> {
    let Some(snapshot) = &inputs.git else {
        return Vec::new();
    };
    let query = current_query();
    snapshot
        .repos
        .iter()
        .filter_map(|repo| {
            let score = best_score(&query, &[&repo.short_name, &repo.path])?;
            Some(SearchResult {
                id: format!("git:{}", repo.path),
                provider: SearchProvider::Git,
                title: repo.short_name.clone(),
                subtitle: format!("{} · {} today", repo.path, repo.today_count),
                score,
                action: SearchAction::Copy(repo.path.clone()),
            })
        })
        .collect()
}

fn weather(inputs: &SearchInputs) -> Vec<SearchResult> {
    let Some(snapshot) = &inputs.weather else {
        return Vec::new();
    };
    let query = current_query();
    let name = if snapshot.location.is_empty() {
        "Weather"
    } else {
        &snapshot.location
    };
    let temp = snapshot
        .condition
        .temp_c
        .map(|value| format!("{value:.0}°C"))
        .unwrap_or_else(|| "—".into());
    let Some(score) = best_score(
        &query,
        &[name, &snapshot.country, &snapshot.condition.desc, &temp],
    ) else {
        return Vec::new();
    };
    vec![SearchResult {
        id: "weather:now".into(),
        provider: SearchProvider::Weather,
        title: name.to_owned(),
        subtitle: format!("{temp} · {}", snapshot.condition.desc),
        score,
        action: SearchAction::Copy(temp),
    }]
}

fn tasks(inputs: &SearchInputs, kind: Option<WorkItemKind>) -> Vec<SearchResult> {
    let Some(snapshot) = &inputs.tasks else {
        return Vec::new();
    };
    let query = current_query();
    snapshot
        .tasks
        .iter()
        .filter(|task| {
            kind.map(|kind| kind.matches(&task.item_type))
                .unwrap_or(true)
        })
        .filter_map(|task| {
            let tags = task.tags.join(" ");
            let haystack = format!("{} {} {} {}", task.id, task.title, task.state, tags);
            let mut score = best_score(&query, &[&haystack])?;
            if query.trim() == task.id {
                score += 1000;
            }
            let action = web_url(&task.url)
                .map(SearchAction::Open)
                .unwrap_or_else(|| SearchAction::Copy(task.id.clone()));
            Some(SearchResult {
                id: format!("task:{}", task.id),
                provider: SearchProvider::Task,
                title: format!("#{} {}", task.id, task.title),
                subtitle: format!("{} · {}", task.item_type, task.state),
                score,
                action,
            })
        })
        .collect()
}

fn prs(inputs: &SearchInputs) -> Vec<SearchResult> {
    let Some(snapshot) = &inputs.prs else {
        return Vec::new();
    };
    let query = current_query();
    snapshot
        .pull_requests
        .iter()
        .filter_map(|pull| {
            let haystack = format!(
                "{} {} #{} {}",
                pull.repo, pull.title, pull.number, pull.number
            );
            let score = best_score(&query, &[&haystack])?;
            let action = web_url(&pull.url)
                .map(SearchAction::Open)
                .unwrap_or_else(|| SearchAction::Copy(format!("#{}", pull.number)));
            Some(SearchResult {
                id: format!("pr:{}", pull.id),
                provider: SearchProvider::Pr,
                title: format!("{} #{} {}", pull.repo, pull.number, pull.title),
                subtitle: format!(
                    "{} · {}",
                    provider_word(pull.provider),
                    if pull.is_draft { "draft" } else { "open" }
                ),
                score,
                action,
            })
        })
        .collect()
}

fn logs(inputs: &SearchInputs) -> Vec<SearchResult> {
    let Some(snapshot) = &inputs.logbox else {
        return Vec::new();
    };
    let query = current_query();
    let mut out = Vec::new();
    for service in &snapshot.services {
        if let Some(score) = best_score(&query, &[&service.name]) {
            out.push(SearchResult {
                id: format!("log:service:{}", service.name),
                provider: SearchProvider::Log,
                title: service.name.clone(),
                subtitle: format!("{} errors", service.count),
                score,
                action: SearchAction::Copy(service.name.clone()),
            });
        }
    }
    for template in &snapshot.templates {
        if let Some(score) = best_score(&query, &[&template.name]) {
            out.push(SearchResult {
                id: format!("log:template:{}", template.name),
                provider: SearchProvider::Log,
                title: template.name.clone(),
                subtitle: format!("{} occurrences", template.count),
                score,
                action: SearchAction::Copy(template.name.clone()),
            });
        }
    }
    for line in &snapshot.recent {
        if let Some(score) = best_score(&query, &[&line.message, &line.service]) {
            out.push(SearchResult {
                id: format!("log:{}:{}", line.at, line.message),
                provider: SearchProvider::Log,
                title: line.message.clone(),
                subtitle: format!("{} · {}", line.service, line.level),
                score,
                action: SearchAction::Copy(line.message.clone()),
            });
        }
    }
    out
}

fn metrics(inputs: &SearchInputs) -> Vec<SearchResult> {
    let Some(snapshot) = &inputs.metricbox else {
        return Vec::new();
    };
    let query = current_query();
    let mut out = Vec::new();
    for host in &snapshot.hosts {
        if let Some(score) = best_score(&query, &[&host.host]) {
            out.push(SearchResult {
                id: format!("metric:host:{}", host.host),
                provider: SearchProvider::Metric,
                title: host.host.clone(),
                subtitle: format!(
                    "CPU {:.0}% · RAM {:.0}% · Disk {:.0}%",
                    host.cpu.unwrap_or(0.0),
                    host.ram.unwrap_or(0.0),
                    host.disk.unwrap_or(0.0)
                ),
                score,
                action: SearchAction::Copy(host.host.clone()),
            });
        }
    }
    for alert in &snapshot.firing_alerts {
        let haystack = format!("{} {} {}", alert.name, alert.host, alert.summary);
        if let Some(score) = best_score(&query, &[&haystack]) {
            out.push(SearchResult {
                id: format!("metric:alert:{}:{}", alert.name, alert.host),
                provider: SearchProvider::Metric,
                title: alert.name.clone(),
                subtitle: [
                    alert.severity.as_str(),
                    alert.host.as_str(),
                    alert.summary.as_str(),
                ]
                .into_iter()
                .filter(|part| !part.is_empty())
                .collect::<Vec<_>>()
                .join(" · "),
                score,
                action: SearchAction::Copy(alert.name.clone()),
            });
        }
    }
    for agent in &snapshot.agents {
        let haystack = format!("{} {}", agent.host, agent.name);
        if let Some(score) = best_score(&query, &[&haystack]) {
            out.push(SearchResult {
                id: format!("metric:agent:{}/{}", agent.host, agent.name),
                provider: SearchProvider::Metric,
                title: format!("{}/{}", agent.host, agent.name),
                subtitle: format!(
                    "CPU {:.0}% · RAM {:.0} MB",
                    agent.cpu.unwrap_or(0.0),
                    agent.ram.unwrap_or(0.0) / 1_048_576.0
                ),
                score,
                action: SearchAction::Copy(agent.name.clone()),
            });
        }
    }
    out
}

fn market(inputs: &SearchInputs) -> Vec<SearchResult> {
    let Some(snapshot) = &inputs.market else {
        return Vec::new();
    };
    let query = current_query();
    snapshot
        .rows
        .iter()
        .filter_map(|row| {
            let score = best_score(&query, &[&row.symbol, &row.name])?;
            let change = row
                .day_change_pct
                .map(|value| format!(" · {value:+.1}%"))
                .unwrap_or_default();
            Some(SearchResult {
                id: format!("mkt:{}", row.symbol),
                provider: SearchProvider::Market,
                title: format!("{} ({})", row.name, row.symbol),
                subtitle: format!(
                    "{:.2} {}{change}",
                    row.price,
                    snapshot.display_currency.label()
                ),
                score,
                action: SearchAction::Copy(row.symbol.clone()),
            })
        })
        .collect()
}

fn status_word(status: ShipStatus) -> &'static str {
    match status {
        ShipStatus::Queued => "Queued",
        ShipStatus::Running => "Running",
        ShipStatus::Success => "Passed",
        ShipStatus::Failure => "Failed",
        ShipStatus::Neutral => "Neutral",
    }
}

fn provider_word(provider: crate::prs::PrProvider) -> &'static str {
    match provider {
        crate::prs::PrProvider::Github => "GitHub",
        crate::prs::PrProvider::AzureDevOps => "Azure",
    }
}

pub fn web_url(raw: &str) -> Option<String> {
    let raw = raw.trim();
    if !(raw.starts_with("https://") || raw.starts_with("http://")) {
        return None;
    }
    let host = raw.split("://").nth(1)?;
    (!host.is_empty() && !host.starts_with('/')).then(|| raw.to_owned())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::devbox::ListeningPort;
    use crate::market::{MarketCurrency, MarketKind, MarketRow, MarketSnapshot};
    use crate::openbox::{OpenCodeSnapshot, SessionRow};
    use crate::prs::{parse_github, PrRole};
    use crate::ship::parse_runs;
    use crate::tasks::parse_work_items;
    use crate::weather::parse as parse_weather;
    use chrono::TimeZone;

    fn now() -> DateTime<Utc> {
        Utc.with_ymd_and_hms(2026, 11, 19, 12, 0, 0)
            .single()
            .expect("date")
    }

    fn empty() -> SearchInputs {
        SearchInputs::default()
    }

    #[test]
    fn a_prefix_scopes_only_after_whitespace() {
        let scoped = parse("port 8080");
        assert_eq!(scoped.scope, Some(SearchProvider::Port));
        assert_eq!(scoped.text, "8080");

        let plain = parse("portfolio");
        assert_eq!(plain.scope, None);
        assert_eq!(plain.text, "portfolio");

        assert_eq!(parse("pr login").scope, Some(SearchProvider::Pr));
        assert_eq!(parse("mkt btc").scope, Some(SearchProvider::Market));
    }

    #[test]
    fn work_item_prefixes_scope_task_and_carry_the_kind() {
        let bug = parse("bug login");
        assert_eq!(bug.scope, Some(SearchProvider::Task));
        assert_eq!(bug.work_item_kind, Some(WorkItemKind::Bug));
        assert_eq!(bug.text, "login");

        let any = parse("wi release");
        assert_eq!(any.work_item_kind, Some(WorkItemKind::Any));
        assert_eq!(
            parse("pbi checkout").work_item_kind,
            Some(WorkItemKind::Backlog)
        );
    }

    #[test]
    fn matching_requires_every_token_and_rewards_exact_hits() {
        assert_eq!(score("deck", "deck"), Some(300));
        assert_eq!(score("dec", "deck"), Some(200));
        assert_eq!(score("linux port", "Linux port"), Some(300));
        assert!(score("linux zzz", "Linux port").is_none());
    }

    #[test]
    fn ports_and_containers_both_answer_under_dev() {
        let mut inputs = empty();
        inputs.ports = vec![ListeningPort {
            protocol: "tcp".into(),
            port: 8080,
        }];
        inputs.containers = vec![DockerContainer {
            name: "redis".into(),
            image: "redis:7".into(),
            status: "Up".into(),
        }];
        let sections = run(&inputs, "redis", now());
        assert_eq!(sections.len(), 1);
        assert_eq!(sections[0].provider, SearchProvider::Port);
        assert_eq!(
            sections[0].results[0].action,
            SearchAction::Copy("redis".into())
        );

        let by_port = run(&inputs, "port 8080", now());
        assert_eq!(by_port[0].results[0].title, "tcp :8080");
    }

    #[test]
    fn clocks_come_from_the_curated_list_and_copy_the_time() {
        let inputs = empty();
        let sections = run(&inputs, "time tokyo", now());
        assert_eq!(sections[0].provider, SearchProvider::Time);
        assert_eq!(sections[0].results[0].title, "Tokyo");
        assert!(sections[0].results[0].subtitle.starts_with("21:00"));
        assert_eq!(
            sections[0].results[0].action,
            SearchAction::Copy("21:00".into())
        );
    }

    #[test]
    fn runs_use_the_fixture_and_open_the_web_url() {
        let runs = parse_runs(include_str!(
            "../../../contracts/fixtures/github_actions_runs.json"
        ))
        .expect("runs")
        .into_iter()
        .map(|mut run| {
            run.repo = "haqaliz/deck".into();
            run
        })
        .collect();
        let mut inputs = empty();
        inputs.ship = Some(ShipBoxSnapshot {
            repos: vec!["haqaliz/deck".into()],
            runs,
            note: None,
        });
        let sections = run(&inputs, "run 42", now());
        assert_eq!(sections[0].provider, SearchProvider::Run);
        assert_eq!(sections[0].results[0].title, "CI #42");
        assert!(matches!(
            sections[0].results[0].action,
            SearchAction::Open(_)
        ));
    }

    #[test]
    fn task_search_filters_by_kind_and_opens_the_item() {
        let tasks = parse_work_items(
            include_str!("../../../contracts/fixtures/azure_workitems.json"),
            "acme",
            "Manifold",
        )
        .expect("tasks");
        let mut inputs = empty();
        inputs.tasks = Some(TaskBoxSnapshot {
            scope: "Manifold".into(),
            total_count: tasks.len(),
            sprint: None,
            tasks,
            note: None,
            total_is_lower_bound: false,
            is_custom_query: false,
        });
        let bug = run(&inputs, "bug flux", now());
        assert_eq!(bug[0].results.len(), 1);
        assert_eq!(bug[0].results[0].title, "#101 Fix the flux capacitor");
        assert!(matches!(bug[0].results[0].action, SearchAction::Open(_)));

        let feature = run(&inputs, "feature flux", now());
        assert!(feature.is_empty());
    }

    #[test]
    fn pull_requests_need_the_prefix_and_market_does_too() {
        let (_, rows) = parse_github(
            include_str!("../../../contracts/fixtures/github_prs.json"),
            PrRole::Authored,
        )
        .expect("prs");
        let mut inputs = empty();
        inputs.prs = Some(PrBoxSnapshot {
            authored_count: rows.len(),
            reviewing_count: 0,
            authored_capped: false,
            reviewing_capped: false,
            pull_requests: rows,
            note: None,
        });
        inputs.market = Some(MarketSnapshot {
            display_currency: MarketCurrency::Usd,
            rows: vec![MarketRow {
                symbol: "BTC".into(),
                name: "Bitcoin".into(),
                kind: MarketKind::Crypto,
                price: 63000.0,
                day_change_pct: Some(1.2),
                sparkline: None,
            }],
            note: None,
        });

        assert!(run(&inputs, "wip", now()).is_empty());
        assert_eq!(
            run(&inputs, "pr wip", now())[0].provider,
            SearchProvider::Pr
        );
        assert!(run(&inputs, "bitcoin", now()).is_empty());
        assert_eq!(
            run(&inputs, "mkt btc", now())[0].provider,
            SearchProvider::Market
        );
    }

    #[test]
    fn weather_git_and_opencode_provide_local_results() {
        let mut inputs = empty();
        inputs.weather = parse_weather(include_str!("../../../contracts/fixtures/weather_j1.json"));
        inputs.git = Some(GitBoxSnapshot {
            today_count: 2,
            streak: 2,
            days: Vec::new(),
            repos: vec![crate::gitbox::RepoInfo {
                short_name: "deck".into(),
                path: "/home/pi/deck".into(),
                today_count: 2,
            }],
        });
        inputs.opencode = Some(OpenCodeSnapshot {
            sessions: 1,
            input: 100,
            output: 50,
            cost: 0.1,
            daily: Vec::new(),
            models: Vec::new(),
            tools: Vec::new(),
            session_list: vec![SessionRow {
                title: "Linux L4 port".into(),
                input: 100,
                output: 50,
                time_created: 0,
            }],
            total_input: 100,
            total_output: 50,
            total_cost: 0.1,
        });

        assert_eq!(
            run(&inputs, "weather amsterdam", now())[0].provider,
            SearchProvider::Weather
        );
        assert_eq!(run(&inputs, "git deck", now())[0].results[0].title, "deck");
        assert_eq!(
            run(&inputs, "oc linux", now())[0].results[0].title,
            "Linux L4 port"
        );
    }

    #[test]
    fn sections_keep_the_documented_order_and_cap() {
        let mut inputs = empty();
        inputs.ports = (1..=8)
            .map(|port| ListeningPort {
                protocol: "tcp".into(),
                port,
            })
            .collect();
        let sections = run(&inputs, "tcp", now());
        assert_eq!(sections[0].provider, SearchProvider::Port);
        assert_eq!(sections[0].results.len(), 5);

        let scoped = run(&inputs, "port tcp", now());
        assert_eq!(scoped[0].results.len(), 8);
    }

    #[test]
    fn web_urls_must_be_http_with_a_host() {
        assert!(web_url("https://github.com/a/b").is_some());
        assert!(web_url("http://dev.azure.com/x").is_some());
        assert!(web_url("javascript:alert(1)").is_none());
        assert!(web_url("https:///missing").is_none());
    }
}

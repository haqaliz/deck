use std::collections::HashMap;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;

use serde::{Deserialize, Serialize};
use time::{Date, Duration, Month, OffsetDateTime};

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct GitBoxSnapshot {
    pub today_count: usize,
    pub streak: usize,
    /// Oldest first, 15 days.
    pub days: Vec<DayCount>,
    pub repos: Vec<RepoInfo>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct DayCount {
    pub day: String,
    pub count: usize,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RepoInfo {
    pub short_name: String,
    pub path: String,
    pub today_count: usize,
}

pub fn parse_log(raw: &str) -> HashMap<String, usize> {
    let mut counts = HashMap::new();
    for line in raw.lines() {
        let day = line.trim();
        if is_day_label(day) {
            *counts.entry(day.to_owned()).or_insert(0) += 1;
        }
    }
    counts
}

pub fn streak(counts: &HashMap<String, usize>, window: &[String]) -> usize {
    let mut index = window.len().saturating_sub(1);
    if window.is_empty() {
        return 0;
    }
    if counts.get(&window[index]).copied().unwrap_or(0) == 0 {
        if index == 0 {
            return 0;
        }
        index -= 1;
    }
    let mut run = 0;
    loop {
        if counts.get(&window[index]).copied().unwrap_or(0) == 0 {
            break;
        }
        run += 1;
        if index == 0 {
            break;
        }
        index -= 1;
    }
    run
}

pub fn day_label(date: Date) -> String {
    format!(
        "{:04}-{:02}-{:02}",
        date.year(),
        date.month() as u8,
        date.day()
    )
}

/// Oldest first, ending today.
pub fn window(today: Date, days: usize) -> Vec<String> {
    (0..days)
        .map(|offset| day_label(today - Duration::days((days - 1 - offset) as i64)))
        .collect()
}

pub fn short_name(path: &str) -> String {
    let trimmed = path.trim_end_matches('/');
    trimmed
        .rsplit('/')
        .next()
        .filter(|name| !name.is_empty())
        .unwrap_or(path)
        .to_owned()
}

/// Local calendar day. Uses libc so DST and the machine's zone are respected;
/// falls back to UTC if the platform cannot answer.
pub fn local_today() -> Date {
    let now = unsafe { libc::time(std::ptr::null_mut()) };
    let mut tm = std::mem::MaybeUninit::<libc::tm>::uninit();
    let result = unsafe { libc::localtime_r(&now, tm.as_mut_ptr()) };
    let fallback = || OffsetDateTime::now_utc().date();
    if result.is_null() {
        return fallback();
    }
    let tm = unsafe { tm.assume_init() };
    let month = match Month::try_from((tm.tm_mon + 1) as u8) {
        Ok(month) => month,
        Err(_) => return fallback(),
    };
    Date::from_calendar_date(tm.tm_year + 1900, month, tm.tm_mday as u8)
        .unwrap_or_else(|_| fallback())
}

pub fn expand_home(raw: &str) -> PathBuf {
    let raw = raw.trim();
    if let Some(rest) = raw.strip_prefix("~/") {
        if let Some(home) = std::env::var_os("HOME") {
            return PathBuf::from(home).join(rest);
        }
    }
    PathBuf::from(raw)
}

pub fn discover_repos(paths: &[String], depth: usize) -> Vec<PathBuf> {
    let mut repos = Vec::new();
    for root in paths {
        let root = expand_home(root);
        if root.is_dir() {
            scan(&root, depth, &mut repos);
        }
    }
    repos
}

fn scan(dir: &Path, depth: usize, repos: &mut Vec<PathBuf>) {
    let Ok(entries) = fs::read_dir(dir) else {
        return;
    };
    let entries: Vec<_> = entries.flatten().collect();
    if entries
        .iter()
        .any(|entry| entry.file_name().to_string_lossy() == ".git")
    {
        repos.push(dir.to_path_buf());
        return;
    }
    if depth == 0 {
        return;
    }
    for entry in entries {
        let name = entry.file_name();
        let name = name.to_string_lossy();
        if name.starts_with('.') {
            continue;
        }
        let Ok(file_type) = entry.file_type() else {
            continue;
        };
        if file_type.is_dir() && !file_type.is_symlink() {
            scan(&entry.path(), depth - 1, repos);
        }
    }
}

fn git_log_days(repo: &Path) -> Option<String> {
    let output = Command::new("git")
        .arg("-C")
        .arg(repo)
        .args([
            "log",
            "--pretty=%ad",
            "--date=format-local:%Y-%m-%d",
            "--since=15.days.ago",
        ])
        .output()
        .ok()?;
    if !output.status.success() {
        return None;
    }
    Some(String::from_utf8_lossy(&output.stdout).into_owned())
}

/// One snapshot over every discovered repo. `None` when no repo was found so
/// the face can say "Add repo paths" instead of showing an empty week.
pub fn sample(paths: &[String], depth: usize) -> Option<GitBoxSnapshot> {
    let repos = discover_repos(paths, depth);
    if repos.is_empty() {
        return None;
    }
    let today = local_today();
    let today_label = day_label(today);
    let window = window(today, 15);

    let mut counts: HashMap<String, usize> = HashMap::new();
    let mut per_repo: Vec<RepoInfo> = Vec::new();
    for repo in &repos {
        let Some(raw) = git_log_days(repo) else {
            continue;
        };
        let repo_counts = parse_log(&raw);
        for (day, count) in &repo_counts {
            *counts.entry(day.clone()).or_insert(0) += count;
        }
        per_repo.push(RepoInfo {
            short_name: short_name(&repo.to_string_lossy()),
            path: repo.to_string_lossy().into_owned(),
            today_count: repo_counts.get(&today_label).copied().unwrap_or(0),
        });
    }

    per_repo.sort_by(|left, right| {
        right
            .today_count
            .cmp(&left.today_count)
            .then_with(|| left.short_name.cmp(&right.short_name))
    });

    Some(GitBoxSnapshot {
        today_count: counts.get(&today_label).copied().unwrap_or(0),
        streak: streak(&counts, &window),
        days: window
            .iter()
            .map(|day| DayCount {
                day: day.clone(),
                count: counts.get(day).copied().unwrap_or(0),
            })
            .collect(),
        repos: per_repo,
    })
}

fn is_day_label(day: &str) -> bool {
    let bytes = day.as_bytes();
    bytes.len() == 10
        && bytes[4] == b'-'
        && bytes[7] == b'-'
        && bytes
            .iter()
            .enumerate()
            .all(|(index, byte)| index == 4 || index == 7 || byte.is_ascii_digit())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_dated_lines_and_ignores_noise() {
        let raw = "2026-11-19\n2026-11-19\n2026-11-18\nnot a date\n2026-1-1\n";
        let counts = parse_log(raw);
        assert_eq!(counts.get("2026-11-19"), Some(&2));
        assert_eq!(counts.get("2026-11-18"), Some(&1));
        assert_eq!(counts.len(), 2);
    }

    #[test]
    fn streak_skips_an_empty_today_but_nothing_else() {
        let window: Vec<String> = window(
            Date::from_calendar_date(2026, Month::January, 15).expect("date"),
            5,
        );
        let mut counts = HashMap::new();
        counts.insert(window[4].clone(), 0);
        counts.insert(window[3].clone(), 2);
        counts.insert(window[2].clone(), 1);
        counts.insert(window[1].clone(), 0);
        assert_eq!(streak(&counts, &window), 2);

        counts.insert(window[4].clone(), 3);
        assert_eq!(streak(&counts, &window), 3);
    }

    #[test]
    fn window_is_oldest_first_and_ends_today() {
        let days = window(
            Date::from_calendar_date(2026, Month::March, 1).expect("date"),
            3,
        );
        assert_eq!(days, vec!["2026-02-27", "2026-02-28", "2026-03-01"]);
    }

    #[test]
    fn short_names_come_from_the_last_path_component() {
        assert_eq!(short_name("/home/pi/deck/"), "deck");
        assert_eq!(short_name("/home/pi/deck"), "deck");
    }

    #[test]
    fn discovery_stops_at_a_git_directory() {
        let tmp = tempfile::tempdir().expect("temp");
        let root = tmp.path();
        fs::create_dir_all(root.join("one/.git")).expect("one");
        fs::create_dir_all(root.join("group/two/.git")).expect("two");
        fs::create_dir_all(root.join("group/three/src")).expect("three");
        let repos = discover_repos(&[root.to_string_lossy().into_owned()], 2);
        let mut names: Vec<String> = repos
            .iter()
            .map(|repo| short_name(&repo.to_string_lossy()))
            .collect();
        names.sort();
        assert_eq!(names, vec!["one", "two"]);
    }
}

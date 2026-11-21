use std::path::PathBuf;
use std::time::Duration;

use deck_core::paths::Paths;
use deck_core::providers::{self, FetchError};
use deck_core::settings::Settings;
use deck_core::snapshot::{self, FetchOutcome};
use deck_core::{gitbox, logbox, market, metricbox, openbox, prs, ship, tasks, weather, CoreError};
use serde::Serialize;

#[derive(Debug, Serialize)]
struct HelloPayload {
    message: &'static str,
    pid: u32,
}

/// One daemon tick: the hello probe plus every enabled widget fetch.
///
/// A failed provider writes its own fetch status and leaves the last good
/// snapshot in place; one dead API must never stop the others.
pub fn run_once(paths: &Paths) -> Result<PathBuf, CoreError> {
    let settings = Settings::load(paths);
    let payload = HelloPayload {
        message: "deckd is alive",
        pid: std::process::id(),
    };
    let path = snapshot::write(paths, "hello", &payload)?;
    snapshot::write_status(paths, "hello", FetchOutcome::Ok)?;
    fetch_all(paths, &settings);
    Ok(path)
}

fn fetch_all(paths: &Paths, settings: &Settings) {
    if settings.weather.enabled {
        run_source(paths, "weather", weather::fetch(&settings.weather.location));
    }
    if settings.git.enabled {
        match gitbox::sample(&settings.git.repo_paths, settings.git.scan_depth as usize) {
            Some(snapshot) => record(paths, "gitbox", Ok(snapshot)),
            None => {
                record::<gitbox::GitBoxSnapshot>(paths, "gitbox", Err(FetchError::NotConfigured))
            }
        }
    }
    if settings.openbox.enabled {
        if settings.openbox.server_url.trim().is_empty() {
            match openbox::load() {
                Ok(Some(snapshot)) => record(paths, "opencode", Ok(snapshot)),
                Ok(None) => record::<openbox::OpenCodeSnapshot>(
                    paths,
                    "opencode",
                    Err(FetchError::NotConfigured),
                ),
                Err(error) => {
                    eprintln!("deckd: opencode: {error}");
                    let _ = snapshot::write_status(paths, "opencode", FetchOutcome::BadResponse);
                }
            }
        } else {
            run_source(
                paths,
                "opencode",
                providers::require_token(paths, "opencode")
                    .and_then(|token| openbox::load_remote(&settings.openbox.server_url, &token)),
            );
        }
    }
    if settings.ship.enabled {
        run_source(
            paths,
            "shipbox",
            providers::require_token(paths, "github").and_then(|token| {
                let repos = if settings.ship.repos.is_empty() {
                    ship::discover_repos(&token, 5)?
                } else {
                    settings.ship.repos.clone()
                };
                ship::fetch(&repos, settings.ship.run_count as usize, &token)
            }),
        );
    }
    if settings.tasks.enabled {
        run_source(
            paths,
            "taskbox",
            providers::require_token(paths, "azure").and_then(|token| {
                tasks::fetch(
                    &settings.tasks.organization,
                    &settings.tasks.project,
                    &token,
                    &settings.tasks.query,
                    settings.tasks.task_count as usize,
                )
            }),
        );
    }
    if settings.prs.enabled {
        let github = settings
            .prs
            .show_github
            .then(|| providers::token(paths, "github").ok().flatten())
            .flatten();
        let azure = settings
            .prs
            .show_azure
            .then(|| providers::token(paths, "azure").ok().flatten())
            .flatten();
        if github.is_none() && azure.is_none() {
            let _ = snapshot::write_status(paths, "prbox", FetchOutcome::NotConfigured);
        } else {
            run_source(
                paths,
                "prbox",
                prs::fetch(prs::PrSources {
                    github_token: github.as_deref(),
                    azure_token: azure.as_deref(),
                    azure_org: &settings.tasks.organization,
                    azure_project: &settings.tasks.project,
                    limit: settings.prs.pr_count as usize,
                    show_review_state: settings.prs.show_review_state,
                }),
            );
        }
    }
    if settings.market.enabled {
        run_source(
            paths,
            "marketbox",
            market::fetch(&settings.market.symbols, settings.market.display_currency),
        );
    }
    if settings.logbox.enabled {
        let previous = snapshot::read_payload::<logbox::LogBoxSnapshot>(paths, "logbox");
        run_source(
            paths,
            "logbox",
            providers::require_token(paths, "elastic").and_then(|key| {
                logbox::fetch(
                    &settings.logbox.base_url,
                    &key,
                    &settings.logbox,
                    previous.as_ref(),
                )
            }),
        );
    }
    if settings.metricbox.enabled {
        run_source(
            paths,
            "metricbox",
            providers::require_token(paths, "grafana").and_then(|token| {
                metricbox::fetch(&settings.metricbox.base_url, &token, &settings.metricbox)
            }),
        );
    }
}

fn run_source<T: Serialize>(paths: &Paths, source: &str, result: Result<T, FetchError>) {
    if let Err(error) = &result {
        eprintln!("deckd: {source}: {}", error.message());
    }
    record(paths, source, result);
}

fn record<T: Serialize>(paths: &Paths, source: &str, result: Result<T, FetchError>) {
    match result {
        Ok(payload) => {
            if let Err(error) = snapshot::write(paths, source, &payload) {
                eprintln!("deckd: {source}: {error}");
            }
            let _ = snapshot::write_status(paths, source, FetchOutcome::Ok);
        }
        Err(error) => {
            let _ = snapshot::write_status(paths, source, error.outcome());
        }
    }
}

pub fn run_forever(paths: &Paths, interval: Duration) -> Result<(), CoreError> {
    loop {
        let path = run_once(paths)?;
        println!("deckd: wrote {}", path.display());
        std::thread::sleep(interval);
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;

    fn temp_paths() -> (tempfile::TempDir, Paths) {
        let tmp = tempfile::tempdir().expect("temp dir");
        let root = tmp.path().to_path_buf();
        (
            tmp,
            Paths::new(root.join("config"), root.join("data"), root.join("cache")),
        )
    }

    #[test]
    fn once_writes_the_v1_snapshot_and_ok_status() {
        let (_tmp, paths) = temp_paths();
        let path = run_once(&paths).expect("run");
        let raw = fs::read_to_string(&path).expect("snapshot");
        assert!(raw.contains("\"schema_version\": 1"));
        assert!(raw.contains("\"source\": \"hello\""));
        assert!(raw.contains("deckd is alive"));

        let status = fs::read_to_string(paths.fetch_status_file("hello")).expect("status");
        assert!(status.contains("\"outcome\": \"ok\""));
    }

    #[test]
    fn disabled_widgets_do_not_write_fetch_status() {
        let (_tmp, paths) = temp_paths();
        run_once(&paths).expect("run");
        assert!(!paths.fetch_status_file("weather").exists());
        assert!(!paths.snapshot_file("weather").exists());
    }

    #[test]
    fn once_creates_directories_on_a_fresh_home() {
        let (_tmp, paths) = temp_paths();
        assert!(!paths.data_dir.exists());
        run_once(&paths).expect("run");
        assert!(paths.data_dir.is_dir());
        assert!(paths.config_dir.is_dir());
    }
}

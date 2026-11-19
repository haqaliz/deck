use std::path::PathBuf;
use std::time::Duration;

use deck_core::paths::Paths;
use deck_core::snapshot::{self, FetchOutcome};
use deck_core::CoreError;
use serde::Serialize;

#[derive(Debug, Serialize)]
struct HelloPayload {
    message: &'static str,
    pid: u32,
}

/// One daemon tick. L1 has no network fetches yet; it proves the snapshot,
/// status and path plumbing end to end.
pub fn run_once(paths: &Paths) -> Result<PathBuf, CoreError> {
    let payload = HelloPayload {
        message: "deckd is alive",
        pid: std::process::id(),
    };
    let path = snapshot::write(paths, "hello", &payload)?;
    snapshot::write_status(paths, "hello", FetchOutcome::Ok)?;
    Ok(path)
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
    fn once_creates_directories_on_a_fresh_home() {
        let (_tmp, paths) = temp_paths();
        assert!(!paths.data_dir.exists());
        run_once(&paths).expect("run");
        assert!(paths.data_dir.is_dir());
        assert!(paths.config_dir.is_dir());
    }
}

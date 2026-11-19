use std::fs;
use std::path::{Path, PathBuf};

use serde::de::DeserializeOwned;
use serde::{Deserialize, Serialize};
use time::format_description::well_known::Rfc3339;
use time::OffsetDateTime;

use crate::paths::{write_atomic, Paths};
use crate::CoreError;

pub const SCHEMA_VERSION: u32 = 1;

/// One widget snapshot. Payload types are added per widget; the envelope is
/// stable so the daemon and the GUI can share it.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct Snapshot<T> {
    pub schema_version: u32,
    pub source: String,
    pub written_at: String,
    pub payload: T,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub enum FetchOutcome {
    Ok,
    NotConfigured,
    AuthOrTarget,
    Unreachable,
    BadResponse,
    CredentialsUnavailable,
    QueryRejected,
    RateLimited,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct FetchStatus {
    pub source: String,
    pub outcome: FetchOutcome,
    pub attempted_at: String,
}

pub fn now_rfc3339() -> String {
    OffsetDateTime::now_utc()
        .format(&Rfc3339)
        .unwrap_or_else(|_| "1970-01-01T00:00:00Z".into())
}

pub fn write<T: Serialize>(paths: &Paths, source: &str, payload: &T) -> Result<PathBuf, CoreError> {
    paths.ensure_dirs()?;
    let snapshot = Snapshot {
        schema_version: SCHEMA_VERSION,
        source: source.to_owned(),
        written_at: now_rfc3339(),
        payload,
    };
    let bytes = serde_json::to_vec_pretty(&snapshot)?;
    let path = paths.snapshot_file(source);
    write_atomic(&path, &bytes, 0o644)?;
    Ok(path)
}

pub fn read<T: DeserializeOwned>(path: &Path) -> Result<Option<Snapshot<T>>, CoreError> {
    let bytes = match fs::read(path) {
        Ok(bytes) => bytes,
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => return Ok(None),
        Err(error) => return Err(error.into()),
    };
    Ok(Some(serde_json::from_slice(&bytes)?))
}

/// Reads the payload of a snapshot without wrapping the error path in the
/// caller: the GUI treats a missing or older file as "no data yet".
pub fn read_payload<T: DeserializeOwned>(paths: &Paths, source: &str) -> Option<T> {
    read::<T>(&paths.snapshot_file(source))
        .ok()
        .flatten()
        .map(|snapshot| snapshot.payload)
}

pub fn read_status(paths: &Paths, source: &str) -> Option<FetchStatus> {
    let bytes = fs::read(paths.fetch_status_file(source)).ok()?;
    serde_json::from_slice(&bytes).ok()
}

pub fn write_status(
    paths: &Paths,
    source: &str,
    outcome: FetchOutcome,
) -> Result<PathBuf, CoreError> {
    paths.ensure_dirs()?;
    let status = FetchStatus {
        source: source.to_owned(),
        outcome,
        attempted_at: now_rfc3339(),
    };
    let bytes = serde_json::to_vec_pretty(&status)?;
    let path = paths.fetch_status_file(source);
    write_atomic(&path, &bytes, 0o644)?;
    Ok(path)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::paths::Paths;

    #[derive(Debug, Serialize, Deserialize, PartialEq)]
    struct Hello {
        message: String,
    }

    fn temp_paths() -> (tempfile::TempDir, Paths) {
        let tmp = tempfile::tempdir().expect("temp dir");
        let root = tmp.path().to_path_buf();
        (
            tmp,
            Paths::new(root.join("config"), root.join("data"), root.join("cache")),
        )
    }

    #[test]
    fn snapshot_round_trip_has_the_v1_envelope() {
        let (_tmp, paths) = temp_paths();
        let payload = Hello {
            message: "alive".into(),
        };
        let path = write(&paths, "hello", &payload).expect("write");
        let raw = fs::read_to_string(&path).expect("read");
        assert!(raw.contains("\"schema_version\": 1"));
        let decoded: Snapshot<Hello> = read(&path).expect("parse").expect("present");
        assert_eq!(decoded.source, "hello");
        assert_eq!(decoded.payload, payload);
        assert!(!decoded.written_at.is_empty());
    }

    #[test]
    fn missing_snapshot_is_none() {
        let (_tmp, paths) = temp_paths();
        let path = paths.snapshot_file("nope");
        assert!(read::<Hello>(&path).expect("read").is_none());
    }

    #[test]
    fn fetch_status_serializes_outcomes_in_camel_case() {
        let (_tmp, paths) = temp_paths();
        let path = write_status(&paths, "hello", FetchOutcome::NotConfigured).expect("status");
        let raw = fs::read_to_string(&path).expect("read");
        assert!(raw.contains("\"notConfigured\""));
        assert!(raw.contains("\"attemptedAt\""));
    }
}

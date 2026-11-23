use serde::{Deserialize, Serialize};

use crate::providers::{self, FetchError};

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Release {
    pub tag: String,
    pub url: String,
    pub published_at: String,
}

/// Latest published GitHub release. This is a check only; installation stays
/// with the package manager / AppImage / Flatpak.
pub fn latest() -> Result<Release, FetchError> {
    let body = providers::get(
        "https://api.github.com/repos/haqaliz/deck/releases/latest",
        &[
            ("Accept", "application/vnd.github+json"),
            ("X-GitHub-Api-Version", "2022-11-28"),
        ],
    )?;
    parse_release(&body).ok_or(FetchError::InvalidPayload)
}

fn parse_release(body: &str) -> Option<Release> {
    let json: serde_json::Value = serde_json::from_str(body).ok()?;
    Some(Release {
        tag: json.get("tag_name")?.as_str()?.to_owned(),
        url: json.get("html_url")?.as_str()?.to_owned(),
        published_at: json
            .get("published_at")
            .and_then(serde_json::Value::as_str)
            .unwrap_or("")
            .to_owned(),
    })
}

/// Numeric comparison of marketplace versions such as `v1.0.0` / `1.0.0`.
pub fn is_newer(current: &str, candidate: &str) -> bool {
    fn parts(value: &str) -> Vec<u64> {
        value
            .trim()
            .trim_start_matches("linux-")
            .trim_start_matches(['v', 'V'])
            .split(['.', '-', '+'])
            .take(3)
            .map(|part| part.parse::<u64>().unwrap_or(0))
            .collect()
    }
    let current = parts(current);
    let candidate = parts(candidate);
    for index in 0..3 {
        let left = current.get(index).copied().unwrap_or(0);
        let right = candidate.get(index).copied().unwrap_or(0);
        if right != left {
            return right > left;
        }
    }
    false
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_latest_release() {
        let body = r#"{"tag_name":"linux-v1.2.3","html_url":"https://example.test/r","published_at":"2026-11-23T00:00:00Z"}"#;
        let release = parse_release(body).expect("release");
        assert_eq!(release.tag, "linux-v1.2.3");
        assert_eq!(release.url, "https://example.test/r");
        assert!(parse_release("{}").is_none());
    }

    #[test]
    fn compares_versions_numerically() {
        assert!(is_newer("1.0.0", "v1.0.1"));
        assert!(is_newer("1.0.0", "linux-v1.1.0"));
        assert!(!is_newer("1.1.0", "1.0.9"));
        assert!(!is_newer("1.0.0", "v1.0.0"));
    }
}

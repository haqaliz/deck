use std::io::Write;
use std::process::{Command, Stdio};

use crate::paths::Paths;
use crate::snapshot::FetchOutcome;

/// A fetch failure mapped onto the shared fetch-status vocabulary.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum FetchError {
    NotConfigured,
    AuthOrTarget,
    Unreachable(String),
    BadResponse(u16),
    CredentialsUnavailable,
    InvalidPayload,
    RateLimited,
}

impl FetchError {
    pub fn outcome(&self) -> FetchOutcome {
        match self {
            Self::NotConfigured => FetchOutcome::NotConfigured,
            Self::AuthOrTarget => FetchOutcome::AuthOrTarget,
            Self::Unreachable(_) => FetchOutcome::Unreachable,
            Self::BadResponse(_) | Self::InvalidPayload => FetchOutcome::BadResponse,
            Self::CredentialsUnavailable => FetchOutcome::CredentialsUnavailable,
            Self::RateLimited => FetchOutcome::RateLimited,
        }
    }

    pub fn message(&self) -> String {
        match self {
            Self::NotConfigured => "not configured".into(),
            Self::AuthOrTarget => "authentication or target rejected".into(),
            Self::Unreachable(reason) => format!("unreachable: {reason}"),
            Self::BadResponse(status) => format!("server returned {status}"),
            Self::CredentialsUnavailable => "credentials unavailable".into(),
            Self::InvalidPayload => "unexpected payload".into(),
            Self::RateLimited => "rate limited".into(),
        }
    }
}

/// HTTPS GET through the system `curl`.
///
/// The request is fed on stdin as a curl config so a token never appears in
/// the process list. Redirects are deliberately not followed: the body is data
/// from the network and the request may carry a token.
pub fn get(url: &str, headers: &[(&str, &str)]) -> Result<String, FetchError> {
    request("GET", url, headers, None)
}

pub fn post(url: &str, headers: &[(&str, &str)], body: &str) -> Result<String, FetchError> {
    request("POST", url, headers, Some(body))
}

pub fn request(
    method: &str,
    url: &str,
    headers: &[(&str, &str)],
    body: Option<&str>,
) -> Result<String, FetchError> {
    let mut config = String::from("silent\nshow-error\nmax-time = 12\n");
    config.push_str("user-agent = \"deck/0.1 (Linux)\"\n");
    config.push_str(&format!("request = \"{method}\"\n"));
    if let Some(body) = body {
        config.push_str(&format!("data = \"{}\"\n", config_escape(body)));
    }
    config.push_str(&format!("url = \"{}\"\n", config_escape(url)));
    config.push_str("write-out = \"\\n%{http_code}\"\n");
    for (name, value) in headers {
        config.push_str(&format!(
            "header = \"{}: {}\"\n",
            config_escape(name),
            config_escape(value)
        ));
    }
    let mut child = Command::new("curl")
        .args(["--config", "-"])
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .map_err(|error| FetchError::Unreachable(format!("curl: {error}")))?;
    if let Some(stdin) = child.stdin.as_mut() {
        stdin
            .write_all(config.as_bytes())
            .map_err(|error| FetchError::Unreachable(format!("curl stdin: {error}")))?;
    }
    let output = child
        .wait_with_output()
        .map_err(|error| FetchError::Unreachable(format!("curl: {error}")))?;
    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr).trim().to_owned();
        return Err(FetchError::Unreachable(if stderr.is_empty() {
            format!("curl exited {:?}", output.status.code())
        } else {
            stderr
        }));
    }
    let text = String::from_utf8_lossy(&output.stdout);
    let (body, status) = text.rsplit_once('\n').ok_or(FetchError::InvalidPayload)?;
    let status: u16 = status.trim().parse().unwrap_or(0);
    match status {
        401 | 403 => Err(FetchError::AuthOrTarget),
        429 => Err(FetchError::RateLimited),
        200..=299 => Ok(body.to_owned()),
        other => Err(FetchError::BadResponse(other)),
    }
}

fn config_escape(value: &str) -> String {
    value
        .chars()
        .filter(|ch| !ch.is_control())
        .collect::<String>()
        .replace('\\', "\\\\")
        .replace('"', "\\\"")
}

pub fn token(paths: &Paths, id: &str) -> Result<Option<String>, FetchError> {
    crate::credentials::CredentialStore::detect(paths)
        .read(id)
        .map_err(|_| FetchError::CredentialsUnavailable)
}

pub fn require_token(paths: &Paths, id: &str) -> Result<String, FetchError> {
    match token(paths, id)? {
        Some(token) if !token.trim().is_empty() => Ok(token),
        _ => Err(FetchError::NotConfigured),
    }
}

/// Normalises a user-entered API base: a scheme and a non-empty host, no
/// trailing slash. Keeps credentials from being sent to a malformed target.
pub fn normalize_base(raw: &str) -> Option<String> {
    let value = raw.trim().trim_end_matches('/');
    if !(value.starts_with("https://") || value.starts_with("http://")) {
        return None;
    }
    let host = value.split("://").nth(1).unwrap_or("");
    (!host.is_empty()).then(|| value.to_owned())
}

pub fn basic_auth(user: &str, token: &str) -> String {
    format!("Basic {}", base64(format!("{user}:{token}").as_bytes()))
}

fn base64(bytes: &[u8]) -> String {
    const TABLE: &[u8; 64] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    let mut out = String::with_capacity(bytes.len().div_ceil(3) * 4);
    for chunk in bytes.chunks(3) {
        let b = [
            chunk[0],
            *chunk.get(1).unwrap_or(&0),
            *chunk.get(2).unwrap_or(&0),
        ];
        out.push(TABLE[(b[0] >> 2) as usize] as char);
        out.push(TABLE[(((b[0] & 0x03) << 4) | (b[1] >> 4)) as usize] as char);
        out.push(if chunk.len() > 1 {
            TABLE[(((b[1] & 0x0f) << 2) | (b[2] >> 6)) as usize] as char
        } else {
            '='
        });
        out.push(if chunk.len() > 2 {
            TABLE[(b[2] & 0x3f) as usize] as char
        } else {
            '='
        });
    }
    out
}

/// Percent-encodes a free-text path segment (city names, symbols).
pub fn encode_path(value: &str) -> String {
    let mut out = String::new();
    for byte in value.trim().bytes() {
        if byte.is_ascii_alphanumeric() || matches!(byte, b'-' | b'_' | b'.' | b'~' | b',') {
            out.push(byte as char);
        } else if byte == b' ' {
            out.push_str("%20");
        } else {
            out.push_str(&format!("%{byte:02X}"));
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn base64_matches_rfc_examples() {
        assert_eq!(base64(b""), "");
        assert_eq!(base64(b"f"), "Zg==");
        assert_eq!(base64(b"fo"), "Zm8=");
        assert_eq!(base64(b"foo"), "Zm9v");
        assert_eq!(base64(b"foobar"), "Zm9vYmFy");
    }

    #[test]
    fn base_urls_require_a_scheme_and_host() {
        assert_eq!(
            normalize_base("https://grafana.example.com/"),
            Some("https://grafana.example.com".into())
        );
        assert_eq!(normalize_base("grafana.example.com"), None);
        assert_eq!(normalize_base("https://"), None);
        assert_eq!(normalize_base(""), None);
    }

    #[test]
    fn path_encodes_spaces_and_keeps_commas() {
        assert_eq!(encode_path("New York"), "New%20York");
        assert_eq!(encode_path("52.3,4.9"), "52.3,4.9");
        assert_eq!(encode_path("Zürich"), "Z%C3%BCrich");
    }

    #[test]
    fn config_values_cannot_break_out_with_quotes_or_newlines() {
        assert_eq!(config_escape("a\"b"), "a\\\"b");
        assert_eq!(config_escape("token\nurl = evil"), "tokenurl = evil");
    }

    #[test]
    fn outcomes_match_the_status_vocabulary() {
        assert_eq!(
            FetchError::CredentialsUnavailable.outcome(),
            FetchOutcome::CredentialsUnavailable
        );
        assert_eq!(
            FetchError::InvalidPayload.outcome(),
            FetchOutcome::BadResponse
        );
    }
}

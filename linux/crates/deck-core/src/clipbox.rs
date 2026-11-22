use std::io::Write;
use std::process::{Command, Stdio};

use serde::{Deserialize, Serialize};

use crate::paths::{write_atomic, Paths};
use crate::CoreError;

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ClipItem {
    pub id: String,
    pub at: String,
    pub kind: String,
    pub preview: String,
    pub detail: String,
    pub content: String,
}

#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ClipBoxSnapshot {
    pub written_at: String,
    pub items: Vec<ClipItem>,
}

fn history_path(paths: &Paths) -> std::path::PathBuf {
    paths.data_dir.join("clipboard.json")
}

pub fn load(paths: &Paths) -> Option<ClipBoxSnapshot> {
    let bytes = std::fs::read(history_path(paths)).ok()?;
    serde_json::from_slice(&bytes).ok()
}

pub fn save(paths: &Paths, snapshot: &ClipBoxSnapshot) -> Result<(), CoreError> {
    paths.ensure_dirs()?;
    let bytes = serde_json::to_vec_pretty(snapshot)?;
    write_atomic(&history_path(paths), &bytes, 0o600)?;
    Ok(())
}

/// Reads the text clipboard. Wayland is preferred because labwc exposes
/// wlr-data-control; X11 falls back to xsel/xclip for non-wlroots sessions.
pub fn read_text() -> Result<String, String> {
    let wayland = std::env::var_os("WAYLAND_DISPLAY").is_some();
    if wayland {
        if let Ok(output) = Command::new("wl-paste")
            .args(["--no-newline", "--type", "text"])
            .output()
        {
            if output.status.success() {
                return Ok(String::from_utf8_lossy(&output.stdout).into_owned());
            }
        }
    }
    for (tool, args) in [
        ("xsel", vec!["--clipboard", "--output"]),
        ("xclip", vec!["-selection", "clipboard", "-o"]),
    ] {
        if let Ok(output) = Command::new(tool).args(args).output() {
            if output.status.success() {
                return Ok(String::from_utf8_lossy(&output.stdout).into_owned());
            }
        }
    }
    Err("no clipboard tool: install wl-clipboard (Wayland) or xsel/xclip (X11)".into())
}

pub fn write_text(text: &str) -> bool {
    if std::env::var_os("WAYLAND_DISPLAY").is_some() {
        if let Ok(mut child) = Command::new("wl-copy").stdin(Stdio::piped()).spawn() {
            if let Some(mut stdin) = child.stdin.take() {
                if stdin.write_all(text.as_bytes()).is_ok() {
                    drop(stdin);
                    return child.wait().map(|status| status.success()).unwrap_or(false);
                }
            }
        }
    }
    for (tool, args) in [
        ("xsel", vec!["--clipboard", "--input"]),
        ("xclip", vec!["-selection", "clipboard", "-i"]),
    ] {
        if let Ok(mut child) = Command::new(tool).args(args).stdin(Stdio::piped()).spawn() {
            if let Some(mut stdin) = child.stdin.take() {
                if stdin.write_all(text.as_bytes()).is_ok() {
                    drop(stdin);
                    return child.wait().map(|status| status.success()).unwrap_or(false);
                }
            }
        }
    }
    false
}

/// Adds one text clip and returns whether the history changed.
pub fn push(snapshot: &mut ClipBoxSnapshot, text: &str, at: &str, cap: usize) -> bool {
    let text = text.trim_end_matches(['\n', '\r']);
    if text.trim().is_empty() {
        return false;
    }
    if snapshot
        .items
        .first()
        .map(|item| item.content == text)
        .unwrap_or(false)
    {
        return false;
    }
    snapshot.items.retain(|item| item.content != text);
    let (kind, detail) = classify(text);
    snapshot.items.insert(
        0,
        ClipItem {
            id: format!("clip:{at}"),
            at: at.to_owned(),
            kind: kind.to_owned(),
            preview: preview(text),
            detail,
            content: text.to_owned(),
        },
    );
    let cap = cap.clamp(1, 200);
    snapshot.items.truncate(cap);
    snapshot.written_at = at.to_owned();
    true
}

fn classify(text: &str) -> (&'static str, String) {
    if text.starts_with("file://") {
        ("file", text.trim_start_matches("file://").to_owned())
    } else if text.starts_with("http://") || text.starts_with("https://") {
        ("file", "link".into())
    } else {
        ("text", String::new())
    }
}

fn preview(text: &str) -> String {
    let line = text.lines().next().unwrap_or(text).trim();
    let mut out: String = line.chars().take(90).collect();
    if line.chars().count() > 90 {
        out.push('…');
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn pushes_new_text_to_the_front_and_deduplicates() {
        let mut snapshot = ClipBoxSnapshot::default();
        assert!(push(&mut snapshot, "one\n", "t1", 10));
        assert!(push(&mut snapshot, "two", "t2", 10));
        assert!(!push(&mut snapshot, "two", "t3", 10));
        assert_eq!(snapshot.items[0].content, "two");
        assert!(push(&mut snapshot, "one", "t4", 10));
        assert_eq!(snapshot.items.len(), 2);
        assert_eq!(snapshot.items[0].content, "one");
    }

    #[test]
    fn caps_history_and_classifies_links() {
        let mut snapshot = ClipBoxSnapshot::default();
        for index in 0..5 {
            push(&mut snapshot, &format!("item {index}"), "t", 3);
        }
        assert_eq!(snapshot.items.len(), 3);
        assert!(push(&mut snapshot, "https://example.com", "t", 3));
        assert_eq!(snapshot.items[0].kind, "file");
    }
}

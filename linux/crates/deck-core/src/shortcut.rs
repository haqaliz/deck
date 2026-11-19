use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;

use crate::paths::write_atomic;
use crate::CoreError;

/// Default Spotlight-style shortcut. L0 proved W-Space fires on labwc.
pub const DEFAULT_KEY: &str = "W-Space";

const MARKER_START: &str = "<!-- deck:search:start -->";
const MARKER_END: &str = "<!-- deck:search:end -->";

/// Write or replace Deck's search keybind in the labwc user config, then ask
/// labwc to reload. The user's other bindings are preserved.
pub fn install_labwc_shortcut(command: &str, key: &str) -> Result<PathBuf, String> {
    let home = std::env::var_os("HOME")
        .map(PathBuf::from)
        .ok_or_else(|| "HOME is not set".to_string())?;
    let rc = home.join(".config/labwc/rc.xml");
    let default_rc = Path::new("/etc/xdg/labwc/rc.xml");

    if !rc.exists() {
        if default_rc.is_file() {
            if let Some(parent) = rc.parent() {
                fs::create_dir_all(parent).map_err(|error| error.to_string())?;
            }
            fs::copy(default_rc, &rc).map_err(|error| error.to_string())?;
        } else {
            if let Some(parent) = rc.parent() {
                fs::create_dir_all(parent).map_err(|error| error.to_string())?;
            }
            let minimal = "<?xml version=\"1.0\"?>\n<openbox_config>\n  <keyboard>\n  </keyboard>\n</openbox_config>\n";
            fs::write(&rc, minimal).map_err(|error| error.to_string())?;
        }
    }

    let original = fs::read_to_string(&rc).map_err(|error| error.to_string())?;
    let updated = apply_shortcut(&original, command, key)
        .ok_or_else(|| "labwc rc.xml has no </keyboard> section".to_string())?;
    write_atomic(&rc, updated.as_bytes(), 0o644).map_err(|error| error.to_string())?;
    reconfigure_labwc();
    Ok(rc)
}

fn apply_shortcut(xml: &str, command: &str, key: &str) -> Option<String> {
    let command = xml_escape(command);
    let block = format!(
        "    {MARKER_START}\n    <keybind key=\"{key}\">\n      <action name=\"Execute\">\n        <command>{command}</command>\n      </action>\n    </keybind>\n    {MARKER_END}\n"
    );

    if let (Some(start), Some(end)) = (xml.find(MARKER_START), xml.find(MARKER_END)) {
        let end = end + MARKER_END.len();
        let mut updated = String::with_capacity(xml.len() + block.len());
        updated.push_str(&xml[..start]);
        updated.push_str(&block);
        updated.push_str(&xml[end..]);
        return Some(updated);
    }

    if !xml.contains("</keyboard>") {
        return None;
    }
    Some(xml.replace("</keyboard>", &format!("{block}  </keyboard>")))
}

fn xml_escape(value: &str) -> String {
    value
        .replace('&', "&amp;")
        .replace('<', "&lt;")
        .replace('>', "&gt;")
        .replace('"', "&quot;")
        .replace('\'', "&apos;")
}

fn reconfigure_labwc() {
    let output = match Command::new("pgrep").args(["-x", "labwc"]).output() {
        Ok(output) => output,
        Err(_) => return,
    };
    if !output.status.success() {
        return;
    }
    let pid = String::from_utf8_lossy(&output.stdout)
        .lines()
        .next()
        .unwrap_or("")
        .trim()
        .to_owned();
    if pid.is_empty() {
        return;
    }
    let _ = Command::new("labwc")
        .arg("--reconfigure")
        .env("LABWC_PID", pid)
        .status();
}

/// Used by the GUI/CLI; kept public so the settings window can report the path.
pub fn labwc_config_path() -> Result<PathBuf, CoreError> {
    let home = std::env::var_os("HOME")
        .map(PathBuf::from)
        .ok_or_else(|| CoreError::Credentials("HOME is not set".into()))?;
    Ok(home.join(".config/labwc/rc.xml"))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn inserts_a_marked_binding_before_the_keyboard_close() {
        let xml = "<openbox_config><keyboard></keyboard></openbox_config>";
        let updated = apply_shortcut(xml, "deck --toggle-search", "W-Space").expect("insert");
        assert!(updated.contains(MARKER_START));
        assert!(updated.contains("key=\"W-Space\""));
        assert!(updated.contains("deck --toggle-search"));
        assert!(updated.ends_with("</keyboard></openbox_config>"));
    }

    #[test]
    fn replaces_an_existing_binding_without_duplicating_it() {
        let xml = "<openbox_config><keyboard></keyboard></openbox_config>";
        let once = apply_shortcut(xml, "deck --toggle-search", "W-Space").expect("first");
        let twice =
            apply_shortcut(&once, "/usr/bin/deck --toggle-search", "A-F12").expect("second");
        assert_eq!(twice.matches(MARKER_START).count(), 1);
        assert!(twice.contains("/usr/bin/deck --toggle-search"));
        assert!(twice.contains("A-F12"));
        assert!(!twice.contains("W-Space"));
    }

    #[test]
    fn refuses_xml_without_a_keyboard_section() {
        assert!(apply_shortcut("<openbox_config/>", "deck", "W-Space").is_none());
    }

    #[test]
    fn escapes_xml_special_characters() {
        assert_eq!(xml_escape("a&b<c>\"d'"), "a&amp;b&lt;c&gt;&quot;d&apos;");
    }
}

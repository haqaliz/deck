use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;

use crate::paths::write_atomic;
use crate::CoreError;

/// KDE autostarts a hidden desktop entry and binds its `_launch` action. The
/// config write is picked up by KGlobalAccel on the next login.
pub const KDE_DESKTOP_ID: &str = "io.github.haqaliz.deck.search.desktop";

pub fn kde_desktop_entry(command: &str) -> String {
    format!(
        "[Desktop Entry]\nType=Application\nName=Deck Search\nComment=Deck Spotlight-style search\nExec={command}\nIcon=deck\nTerminal=false\nNoDisplay=true\nStartupNotify=false\n"
    )
}

fn kde_key(key: &str) -> String {
    key.split('-')
        .map(|part| match part {
            "W" => "Meta",
            "A" => "Alt",
            "C" => "Ctrl",
            "S" => "Shift",
            other => other,
        })
        .collect::<Vec<_>>()
        .join("+")
}

fn kwriteconfig() -> Option<&'static str> {
    ["kwriteconfig6", "kwriteconfig5"].into_iter().find(|tool| {
        Command::new(tool)
            .arg("--version")
            .output()
            .map(|output| output.status.success())
            .unwrap_or(false)
    })
}

pub fn install_kde_shortcut(command: &str, key: &str) -> Result<PathBuf, String> {
    let home = std::env::var_os("HOME")
        .map(PathBuf::from)
        .ok_or_else(|| "HOME is not set".to_string())?;
    let tool = kwriteconfig().ok_or_else(|| "kwriteconfig6/kwriteconfig5 not found".to_string())?;
    let desktop = home.join(".local/share/applications").join(KDE_DESKTOP_ID);
    if let Some(parent) = desktop.parent() {
        fs::create_dir_all(parent).map_err(|error| error.to_string())?;
    }
    write_atomic(&desktop, kde_desktop_entry(command).as_bytes(), 0o644)
        .map_err(|error| error.to_string())?;

    let value = format!("{},{},Deck Search", kde_key(key), "none");
    let status = Command::new(tool)
        .args([
            "--file",
            "kglobalshortcutsrc",
            "--group",
            "services",
            "--group",
            KDE_DESKTOP_ID,
            "--key",
            "_launch",
        ])
        .arg(value)
        .status()
        .map_err(|error| format!("{tool}: {error}"))?;
    if !status.success() {
        return Err(format!("{tool} could not write kglobalshortcutsrc"));
    }
    for tool in ["kbuildsycoca6", "kbuildsycoca5"] {
        if Command::new(tool).arg("--noincremental").status().is_ok() {
            break;
        }
    }
    Ok(desktop)
}

/// Removes the hidden launcher and KGlobalAccel entry. `Ok(None)` means neither
/// existed.
pub fn remove_kde_shortcut() -> Result<Option<PathBuf>, String> {
    let home = std::env::var_os("HOME")
        .map(PathBuf::from)
        .ok_or_else(|| "HOME is not set".to_string())?;
    let desktop = home.join(".local/share/applications").join(KDE_DESKTOP_ID);
    let mut removed = None;
    if desktop.exists() {
        fs::remove_file(&desktop).map_err(|error| error.to_string())?;
        removed = Some(desktop);
    }
    if let Some(tool) = kwriteconfig() {
        let _ = Command::new(tool)
            .args([
                "--file",
                "kglobalshortcutsrc",
                "--group",
                "services",
                "--group",
                KDE_DESKTOP_ID,
                "--key",
                "_launch",
                "--delete",
            ])
            .status();
    }
    Ok(removed)
}

/// Default Spotlight-style shortcut. L0 proved W-Space fires on labwc.
pub const DEFAULT_KEY: &str = "W-Space";

const MARKER_START: &str = "<!-- deck:search:start -->";
const MARKER_END: &str = "<!-- deck:search:end -->";
const DESKTOP_START: &str = "<!-- deck:desktop:start -->";
const DESKTOP_END: &str = "<!-- deck:desktop:end -->";

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

/// Puts the PCManFM desktop window on the always-on-bottom layer so it cannot
/// swallow pointer input aimed at Deck's bottom-layer widgets. Runs once;
/// other window rules are preserved.
pub fn ensure_labwc_desktop_rule() -> Result<Option<PathBuf>, String> {
    let rc = labwc_config_path().map_err(|error| error.to_string())?;
    if !rc.exists() {
        return Ok(None);
    }
    let original = fs::read_to_string(&rc).map_err(|error| error.to_string())?;
    if original.contains(DESKTOP_START) {
        return Ok(None);
    }
    let Some(updated) = apply_desktop_rule(&original) else {
        return Ok(None);
    };
    write_atomic(&rc, updated.as_bytes(), 0o644).map_err(|error| error.to_string())?;
    reconfigure_labwc();
    Ok(Some(rc))
}

pub fn remove_labwc_desktop_rule() -> Result<Option<PathBuf>, String> {
    let rc = labwc_config_path().map_err(|error| error.to_string())?;
    if !rc.exists() {
        return Ok(None);
    }
    let original = fs::read_to_string(&rc).map_err(|error| error.to_string())?;
    let Some(updated) = strip_marked(&original, DESKTOP_START, DESKTOP_END) else {
        return Ok(None);
    };
    write_atomic(&rc, updated.as_bytes(), 0o644).map_err(|error| error.to_string())?;
    reconfigure_labwc();
    Ok(Some(rc))
}

fn apply_desktop_rule(xml: &str) -> Option<String> {
    if xml.contains(DESKTOP_START) {
        return None;
    }
    let block = format!(
        "    {DESKTOP_START}\n    <windowRule identifier=\"pcmanfm\"><action name=\"ToggleAlwaysOnBottom\"/></windowRule>\n    <windowRule identifier=\"pcmanfm-pi\"><action name=\"ToggleAlwaysOnBottom\"/></windowRule>\n    <windowRule title=\"*pcmanfm*\"><action name=\"ToggleAlwaysOnBottom\"/></windowRule>\n    {DESKTOP_END}\n"
    );
    if xml.contains("</windowRules>") {
        return Some(xml.replace("</windowRules>", &format!("{block}  </windowRules>")));
    }
    if xml.contains("</openbox_config>") {
        let section = format!("  <windowRules>\n{block}  </windowRules>\n");
        return Some(xml.replace("</openbox_config>", &format!("{section}</openbox_config>")));
    }
    None
}

/// Removes Deck's marked block and reconfigures labwc. `Ok(None)` means there
/// was nothing to remove.
pub fn remove_labwc_shortcut() -> Result<Option<PathBuf>, String> {
    let rc = labwc_config_path().map_err(|error| error.to_string())?;
    if !rc.exists() {
        return Ok(None);
    }
    let original = fs::read_to_string(&rc).map_err(|error| error.to_string())?;
    let Some(updated) = strip_shortcut(&original) else {
        return Ok(None);
    };
    write_atomic(&rc, updated.as_bytes(), 0o644).map_err(|error| error.to_string())?;
    reconfigure_labwc();
    Ok(Some(rc))
}

fn strip_shortcut(xml: &str) -> Option<String> {
    strip_marked(xml, MARKER_START, MARKER_END)
}

fn strip_marked(xml: &str, marker_start: &str, marker_end: &str) -> Option<String> {
    let start = xml.find(marker_start)?;
    let end = xml.find(marker_end)? + marker_end.len();
    let mut updated = String::with_capacity(xml.len());
    updated.push_str(&xml[..start]);
    updated.push_str(xml[end..].trim_start_matches(['\n', '\r']));
    Some(updated)
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
    fn removes_only_the_marked_block() {
        let xml = "<openbox_config><keyboard>\n  <keybind key=\"A-Tab\"/>\n<!-- deck:search:start -->\n<keybind key=\"W-Space\"/>\n<!-- deck:search:end -->\n</keyboard></openbox_config>";
        let stripped = strip_shortcut(xml).expect("strip");
        assert!(!stripped.contains(MARKER_START));
        assert!(!stripped.contains("W-Space"));
        assert!(stripped.contains("A-Tab"));
        assert!(strip_shortcut("<openbox_config/>").is_none());
    }

    #[test]
    fn adds_the_desktop_rule_once_and_keeps_user_rules() {
        let xml = "<openbox_config><windowRules><windowRule identifier=\"Kodi\"/></windowRules></openbox_config>";
        let once = apply_desktop_rule(xml).expect("rule");
        assert_eq!(once.matches(DESKTOP_START).count(), 1);
        assert!(once.contains("pcmanfm"));
        assert!(once.contains("Kodi"));
        assert!(apply_desktop_rule(&once).is_none());
    }

    #[test]
    fn adds_a_window_rules_section_when_missing() {
        let xml = "<openbox_config><theme/></openbox_config>";
        let updated = apply_desktop_rule(xml).expect("rule");
        assert!(updated.contains("<windowRules>"));
        assert!(updated.contains(DESKTOP_START));
        assert!(updated.ends_with("</openbox_config>"));
    }

    #[test]
    fn removes_the_desktop_rule_without_touching_others() {
        let xml = "<openbox_config><windowRules><windowRule identifier=\"Kodi\"/></windowRules></openbox_config>";
        let with_rule = apply_desktop_rule(xml).expect("rule");
        let stripped = strip_marked(&with_rule, DESKTOP_START, DESKTOP_END).expect("strip");
        assert!(!stripped.contains("pcmanfm"));
        assert!(stripped.contains("Kodi"));
    }

    #[test]
    fn refuses_xml_without_a_keyboard_section() {
        assert!(apply_shortcut("<openbox_config/>", "deck", "W-Space").is_none());
    }

    #[test]
    fn kde_entry_and_key_are_well_formed() {
        let entry = kde_desktop_entry("/usr/bin/deck --toggle-search");
        assert!(entry.contains("Exec=/usr/bin/deck --toggle-search"));
        assert!(entry.contains("NoDisplay=true"));
        assert_eq!(kde_key("W-Space"), "Meta+Space");
        assert_eq!(kde_key("C-A-F12"), "Ctrl+Alt+F12");
    }

    #[test]
    fn escapes_xml_special_characters() {
        assert_eq!(xml_escape("a&b<c>\"d'"), "a&amp;b&lt;c&gt;&quot;d&apos;");
    }
}

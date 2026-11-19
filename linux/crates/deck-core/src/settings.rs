use std::fs;
use std::path::Path;

use serde::{Deserialize, Serialize};

use crate::paths::{write_atomic, Paths};

/// Settings that are not widget-specific. Widget sections arrive with the
/// widgets in L2-L5; the top-level file is already tolerant so adding them
/// never resets a user's existing choices.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(default)]
pub struct Settings {
    pub schema_version: u32,
    pub autostart: bool,
    pub theme: Theme,
    pub search_shortcut: Option<String>,
}

impl Default for Settings {
    fn default() -> Self {
        Self {
            schema_version: 1,
            autostart: true,
            theme: Theme::System,
            search_shortcut: None,
        }
    }
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum Theme {
    System,
    Light,
    Dark,
}

impl Settings {
    /// Missing file -> defaults. Unreadable/corrupt file -> move it aside and
    /// return defaults, so one bad byte cannot stop the daemon or the GUI.
    pub fn load(paths: &Paths) -> Self {
        let file = paths.settings_file();
        let raw = match fs::read_to_string(&file) {
            Ok(raw) => raw,
            Err(_) => return Self::default(),
        };
        match serde_json::from_str(&raw) {
            Ok(settings) => settings,
            Err(_) => {
                backup_corrupt(&file);
                Self::default()
            }
        }
    }

    pub fn save(&self, paths: &Paths) -> Result<(), crate::CoreError> {
        paths.ensure_dirs()?;
        let bytes = serde_json::to_vec_pretty(self)?;
        write_atomic(&paths.settings_file(), &bytes, 0o644)?;
        Ok(())
    }
}

fn backup_corrupt(file: &Path) {
    let name = file
        .file_name()
        .and_then(|n| n.to_str())
        .unwrap_or("settings.json");
    let stamp = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0);
    let backup = file.with_file_name(format!("{name}.corrupt.{stamp}"));
    let _ = fs::rename(file, backup);
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::paths::Paths;

    fn temp_paths() -> (tempfile::TempDir, Paths) {
        let tmp = tempfile::tempdir().expect("temp dir");
        let root = tmp.path().to_path_buf();
        (
            tmp,
            Paths::new(root.join("config"), root.join("data"), root.join("cache")),
        )
    }

    #[test]
    fn missing_file_returns_defaults() {
        let (_tmp, paths) = temp_paths();
        assert_eq!(Settings::load(&paths), Settings::default());
    }

    #[test]
    fn settings_round_trip() {
        let (_tmp, paths) = temp_paths();
        let settings = Settings {
            autostart: false,
            theme: Theme::Dark,
            search_shortcut: Some("Super+Space".into()),
            ..Settings::default()
        };
        settings.save(&paths).expect("save");
        assert_eq!(Settings::load(&paths), settings);
    }

    #[test]
    fn corrupt_settings_are_moved_aside_and_defaults_return() {
        let (_tmp, paths) = temp_paths();
        paths.ensure_dirs().expect("dirs");
        fs::write(paths.settings_file(), b"{not json").expect("write corrupt");
        assert_eq!(Settings::load(&paths), Settings::default());
        let backups = fs::read_dir(&paths.config_dir)
            .expect("dir")
            .filter_map(Result::ok)
            .filter(|entry| entry.file_name().to_string_lossy().contains(".corrupt."))
            .count();
        assert_eq!(backups, 1);
    }
}

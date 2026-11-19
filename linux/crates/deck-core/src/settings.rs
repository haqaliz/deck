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
    pub livebox: LiveBoxSettings,
    pub netbox: NetBoxSettings,
    pub devbox: DevBoxSettings,
}

impl Default for Settings {
    fn default() -> Self {
        Self {
            schema_version: 1,
            autostart: true,
            theme: Theme::System,
            search_shortcut: None,
            livebox: LiveBoxSettings::default(),
            netbox: NetBoxSettings::default(),
            devbox: DevBoxSettings::default(),
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(default)]
pub struct LiveBoxSettings {
    pub enabled: bool,
    pub size: WidgetSize,
    pub show_cpu: bool,
    pub show_mem: bool,
    pub show_disk: bool,
    pub show_gpu: bool,
    pub show_processes: bool,
    pub show_chart: bool,
    pub process_count: u8,
    pub refresh_seconds: u64,
    pub cpu_warn: u8,
    pub cpu_alarm: u8,
    pub mem_warn: u8,
    pub mem_alarm: u8,
    pub disk_warn: u8,
    pub disk_alarm: u8,
    pub gpu_warn: u8,
    pub gpu_alarm: u8,
}

impl Default for LiveBoxSettings {
    fn default() -> Self {
        Self {
            enabled: true,
            size: WidgetSize::Large,
            show_cpu: true,
            show_mem: true,
            show_disk: true,
            show_gpu: true,
            show_processes: true,
            show_chart: true,
            process_count: 3,
            refresh_seconds: 15,
            cpu_warn: 80,
            cpu_alarm: 90,
            mem_warn: 80,
            mem_alarm: 90,
            disk_warn: 80,
            disk_alarm: 90,
            gpu_warn: 80,
            gpu_alarm: 90,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(default)]
pub struct NetBoxSettings {
    pub enabled: bool,
    pub size: WidgetSize,
    /// Empty means every interface, sorted by traffic.
    pub interface: String,
    pub interface_count: u8,
    pub refresh_seconds: u64,
    pub show_packets: bool,
    pub show_chart: bool,
    /// Thresholds in MB/s (decimal), like the macOS NetBox.
    pub warn_mbps: u16,
    pub alarm_mbps: u16,
}

impl Default for NetBoxSettings {
    fn default() -> Self {
        Self {
            enabled: true,
            size: WidgetSize::Medium,
            interface: String::new(),
            interface_count: 3,
            refresh_seconds: 5,
            show_packets: true,
            show_chart: true,
            warn_mbps: 50,
            alarm_mbps: 100,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(default)]
pub struct DevBoxSettings {
    pub enabled: bool,
    pub size: WidgetSize,
    pub show_ports: bool,
    pub show_containers: bool,
    pub port_count: u8,
    pub container_count: u8,
    pub refresh_seconds: u64,
}

impl Default for DevBoxSettings {
    fn default() -> Self {
        Self {
            enabled: true,
            size: WidgetSize::Large,
            show_ports: true,
            show_containers: true,
            port_count: 5,
            container_count: 5,
            refresh_seconds: 10,
        }
    }
}

#[derive(Debug, Clone, Copy, Default, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "lowercase")]
pub enum WidgetSize {
    Small,
    #[default]
    Medium,
    Large,
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
    fn system_widget_sections_default_when_missing() {
        let parsed: Settings = serde_json::from_str("{\"schema_version\":1}").expect("parse");
        assert!(parsed.livebox.enabled);
        assert_eq!(parsed.livebox.refresh_seconds, 15);
        assert!(parsed.netbox.enabled);
        assert_eq!(parsed.netbox.refresh_seconds, 5);
        assert!(parsed.devbox.show_ports);
        assert_eq!(parsed.devbox.refresh_seconds, 10);
        assert_eq!(parsed.livebox.size, WidgetSize::Large);
        assert_eq!(parsed.netbox.size, WidgetSize::Medium);
        assert_eq!(parsed.netbox.interface_count, 3);
        assert_eq!(parsed.devbox.port_count, 5);
    }

    #[test]
    fn widget_size_round_trips_as_lowercase() {
        let mut settings = Settings::default();
        settings.livebox.size = WidgetSize::Small;
        let json = serde_json::to_string(&settings).expect("serialize");
        assert!(json.contains("\"size\":\"small\""));
        let parsed: Settings = serde_json::from_str(&json).expect("parse");
        assert_eq!(parsed.livebox.size, WidgetSize::Small);
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

use std::fs;
use std::path::Path;

use serde::{Deserialize, Serialize};

use crate::market::MarketCurrency;
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
    pub surface_mode: SurfaceMode,
    pub search_shortcut: Option<String>,
    pub livebox: LiveBoxSettings,
    pub netbox: NetBoxSettings,
    pub devbox: DevBoxSettings,
    pub weather: WeatherBoxSettings,
    pub clock: ClockBoxSettings,
    pub git: GitBoxSettings,
    pub openbox: OpenBoxSettings,
    pub ship: ShipBoxSettings,
    pub tasks: TaskBoxSettings,
    pub prs: PrBoxSettings,
    pub market: MarketBoxSettings,
    pub logbox: LogBoxSettings,
    pub metricbox: MetricBoxSettings,
}

impl Default for Settings {
    fn default() -> Self {
        Self {
            schema_version: 1,
            autostart: true,
            theme: Theme::System,
            surface_mode: SurfaceMode::Auto,
            search_shortcut: None,
            livebox: LiveBoxSettings::default(),
            netbox: NetBoxSettings::default(),
            devbox: DevBoxSettings::default(),
            weather: WeatherBoxSettings::default(),
            clock: ClockBoxSettings::default(),
            git: GitBoxSettings::default(),
            openbox: OpenBoxSettings::default(),
            ship: ShipBoxSettings::default(),
            tasks: TaskBoxSettings::default(),
            prs: PrBoxSettings::default(),
            market: MarketBoxSettings::default(),
            logbox: LogBoxSettings::default(),
            metricbox: MetricBoxSettings::default(),
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

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(default)]
pub struct WeatherBoxSettings {
    pub enabled: bool,
    pub size: WidgetSize,
    pub location: String,
    pub units_fahrenheit: bool,
    pub show_forecast: bool,
}

impl Default for WeatherBoxSettings {
    fn default() -> Self {
        Self {
            enabled: false,
            size: WidgetSize::Medium,
            location: String::new(),
            units_fahrenheit: false,
            show_forecast: true,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(default)]
pub struct ClockBoxSettings {
    pub enabled: bool,
    pub size: WidgetSize,
    /// IANA identifiers, plus the `local` sentinel.
    pub city_ids: Vec<String>,
    pub main_city_id: String,
    pub show_relative_day: bool,
    pub show_offset: bool,
}

impl Default for ClockBoxSettings {
    fn default() -> Self {
        Self {
            enabled: false,
            size: WidgetSize::Medium,
            city_ids: vec!["local".into(), "UTC".into()],
            main_city_id: String::new(),
            show_relative_day: true,
            show_offset: true,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(default)]
pub struct GitBoxSettings {
    pub enabled: bool,
    pub size: WidgetSize,
    pub repo_paths: Vec<String>,
    pub scan_depth: u8,
    pub show_chart: bool,
    pub show_repos: bool,
    pub repo_count: u8,
}

impl Default for GitBoxSettings {
    fn default() -> Self {
        Self {
            enabled: false,
            size: WidgetSize::Medium,
            repo_paths: Vec::new(),
            scan_depth: 3,
            show_chart: true,
            show_repos: true,
            repo_count: 5,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(default)]
pub struct OpenBoxSettings {
    pub enabled: bool,
    pub size: WidgetSize,
    pub show_models: bool,
    pub show_tools: bool,
    pub show_sessions: bool,
    pub model_count: u8,
    pub tool_count: u8,
    pub session_count: u8,
}

impl Default for OpenBoxSettings {
    fn default() -> Self {
        Self {
            enabled: false,
            size: WidgetSize::Medium,
            show_models: true,
            show_tools: false,
            show_sessions: false,
            model_count: 3,
            tool_count: 3,
            session_count: 3,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(default)]
pub struct ShipBoxSettings {
    pub enabled: bool,
    pub size: WidgetSize,
    /// "owner/repo" entries.
    pub repos: Vec<String>,
    pub run_count: u8,
    pub show_list: bool,
}

impl Default for ShipBoxSettings {
    fn default() -> Self {
        Self {
            enabled: false,
            size: WidgetSize::Medium,
            repos: Vec::new(),
            run_count: 4,
            show_list: true,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(default)]
pub struct TaskBoxSettings {
    pub enabled: bool,
    pub size: WidgetSize,
    pub organization: String,
    pub project: String,
    pub query: String,
    pub task_count: u8,
    pub show_legend: bool,
    pub show_list: bool,
}

impl Default for TaskBoxSettings {
    fn default() -> Self {
        Self {
            enabled: false,
            size: WidgetSize::Medium,
            organization: String::new(),
            project: String::new(),
            query: String::new(),
            task_count: 5,
            show_legend: true,
            show_list: true,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(default)]
pub struct PrBoxSettings {
    pub enabled: bool,
    pub size: WidgetSize,
    pub pr_count: u8,
    pub show_list: bool,
}

impl Default for PrBoxSettings {
    fn default() -> Self {
        Self {
            enabled: false,
            size: WidgetSize::Medium,
            pr_count: 6,
            show_list: true,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(default)]
pub struct MarketBoxSettings {
    pub enabled: bool,
    pub size: WidgetSize,
    pub symbols: Vec<String>,
    pub display_currency: MarketCurrency,
    pub ticker_count: u8,
    pub show_day_change: bool,
}

impl Default for MarketBoxSettings {
    fn default() -> Self {
        Self {
            enabled: false,
            size: WidgetSize::Medium,
            symbols: vec!["BTC".into(), "ETH".into(), "GOLD".into(), "AAPL".into()],
            display_currency: MarketCurrency::Usd,
            ticker_count: 8,
            show_day_change: true,
        }
    }
}

#[derive(Debug, Clone, Copy, Default, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "lowercase")]
pub enum LogTextMode {
    #[default]
    Templates,
    Latest,
    Full,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(default)]
pub struct LogBoxSettings {
    pub enabled: bool,
    pub size: WidgetSize,
    pub base_url: String,
    /// `prd`, `stg` or a full `logs-manifold-*` stream name.
    pub environment: String,
    pub service: String,
    pub text_mode: LogTextMode,
    pub small_minutes: u16,
    pub large_minutes: u16,
    pub show_trend: bool,
}

impl Default for LogBoxSettings {
    fn default() -> Self {
        Self {
            enabled: false,
            size: WidgetSize::Medium,
            base_url: String::new(),
            environment: "logs-manifold-prd".into(),
            service: String::new(),
            text_mode: LogTextMode::Templates,
            small_minutes: 15,
            large_minutes: 1440,
            show_trend: true,
        }
    }
}

#[derive(Debug, Clone, Copy, Default, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "lowercase")]
pub enum MetricBoxFace {
    #[default]
    Fleet,
    Host,
    Power,
    Agents,
    Alerts,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(default)]
pub struct MetricBoxSettings {
    pub enabled: bool,
    pub size: WidgetSize,
    pub base_url: String,
    pub face: MetricBoxFace,
    /// Empty means all hosts; used by the Host face.
    pub host: String,
    /// USD cents per kWh; integer so the settings file stays Eq.
    pub rate_per_kwh_cents: u16,
    pub large_window_minutes: u16,
    pub show_cpu: bool,
    pub show_ram: bool,
    pub show_disk: bool,
    pub show_gpu: bool,
    pub show_power: bool,
}

impl Default for MetricBoxSettings {
    fn default() -> Self {
        Self {
            enabled: false,
            size: WidgetSize::Medium,
            base_url: String::new(),
            face: MetricBoxFace::Fleet,
            host: String::new(),
            rate_per_kwh_cents: 12,
            large_window_minutes: 1440,
            show_cpu: true,
            show_ram: true,
            show_disk: true,
            show_gpu: true,
            show_power: true,
        }
    }
}

#[derive(Debug, Clone, Copy, Default, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "lowercase")]
pub enum SurfaceMode {
    #[default]
    Auto,
    LayerShell,
    X11,
    Dashboard,
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
        assert_eq!(parsed.surface_mode, SurfaceMode::Auto);
        assert_eq!(parsed.livebox.size, WidgetSize::Large);
        assert_eq!(parsed.netbox.size, WidgetSize::Medium);
        assert_eq!(parsed.netbox.interface_count, 3);
        assert_eq!(parsed.devbox.port_count, 5);
        assert!(!parsed.weather.enabled);
        assert_eq!(parsed.weather.size, WidgetSize::Medium);
        assert_eq!(parsed.clock.city_ids, vec!["local", "UTC"]);
        assert_eq!(parsed.market.display_currency, MarketCurrency::Usd);
        assert_eq!(parsed.market.symbols.len(), 4);
        assert!(!parsed.ship.enabled);
        assert!(!parsed.logbox.enabled);
        assert_eq!(parsed.logbox.text_mode, LogTextMode::Templates);
        assert!(!parsed.metricbox.enabled);
        assert_eq!(parsed.metricbox.face, MetricBoxFace::Fleet);
        assert_eq!(parsed.metricbox.rate_per_kwh_cents, 12);
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

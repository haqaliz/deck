use std::collections::BTreeMap;
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
    #[serde(default = "default_schema_version")]
    pub schema_version: u32,
    pub autostart: bool,
    pub theme: Theme,
    pub surface_mode: SurfaceMode,
    /// Last dragged position per widget title (and "Search"). Empty means the
    /// automatic flow is used.
    pub positions: BTreeMap<String, WindowPosition>,
    pub search_shortcut: Option<String>,
    pub search: SearchSettings,
    /// Extra Azure DevOps accounts. The legacy `tasks.organization`/`project`
    /// plus the `azure` token stay valid when this list is empty.
    pub azure_accounts: Vec<AzureAccount>,
    pub livebox: LiveBoxSettings,
    pub calbox: CalBoxSettings,
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

fn default_schema_version() -> u32 {
    1
}

impl Default for Settings {
    fn default() -> Self {
        Self {
            schema_version: 1,
            autostart: true,
            theme: Theme::System,
            surface_mode: SurfaceMode::Auto,
            positions: BTreeMap::new(),
            search_shortcut: None,
            search: SearchSettings::default(),
            azure_accounts: Vec::new(),
            livebox: LiveBoxSettings::default(),
            calbox: CalBoxSettings::default(),
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

#[derive(Debug, Clone, Default, Serialize, Deserialize, PartialEq, Eq)]
#[serde(default)]
pub struct AzureAccount {
    /// Credential store id and the value stored in a widget's account field.
    pub id: String,
    pub label: String,
    pub organization: String,
    pub project: String,
}

impl Settings {
    /// Resolves the selected Azure account, falling back to the legacy fields.
    pub fn azure_account(&self, selected: &str) -> (&str, &str, &str) {
        if let Some(account) = self
            .azure_accounts
            .iter()
            .find(|account| account.id == selected)
        {
            (&account.id, &account.organization, &account.project)
        } else {
            ("azure", &self.tasks.organization, &self.tasks.project)
        }
    }
}

#[derive(Debug, Clone, Default, Serialize, Deserialize, PartialEq, Eq)]
#[serde(default)]
pub struct SearchSettings {
    /// Provider ids the user turned off: port, time, oc, run, sys, net, git,
    /// weather, task, pr, log, metric, mkt.
    pub disabled: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(default)]
pub struct CalBoxSettings {
    pub enabled: bool,
    pub size: WidgetSize,
    pub server_url: String,
    pub username: String,
    pub show_all_day: bool,
    pub show_today: bool,
    pub show_tomorrow: bool,
    pub today_count: u8,
    pub tomorrow_count: u8,
    pub use_calendar_colors: bool,
    /// Used when calendar colours are off.
    pub accent_color: String,
}

impl Default for CalBoxSettings {
    fn default() -> Self {
        Self {
            enabled: false,
            size: WidgetSize::Medium,
            server_url: String::new(),
            username: String::new(),
            show_all_day: true,
            show_today: true,
            show_tomorrow: true,
            today_count: 6,
            tomorrow_count: 4,
            use_calendar_colors: true,
            accent_color: "#0a84ff".into(),
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
    pub show_per_core_cores: bool,
    pub cpu_color: String,
    pub mem_color: String,
    pub disk_color: String,
    pub gpu_color: String,
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
            show_per_core_cores: false,
            cpu_color: "#30d158".into(),
            mem_color: "#40c8e0".into(),
            disk_color: "#ff9f0a".into(),
            gpu_color: "#bf5af2".into(),
            process_count: 10,
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
    /// Empty reads the local SQLite database; otherwise an `opencode serve`
    /// base URL and the `opencode` credential are used.
    pub server_url: String,
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
            server_url: String::new(),
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
    /// Empty uses the legacy `organization`/`project` and `azure` token.
    pub account_id: String,
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
            account_id: String::new(),
            organization: String::new(),
            project: String::new(),
            query: String::new(),
            task_count: 12,
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
    /// Empty uses the legacy Tasks organization/project and `azure` token.
    pub azure_account_id: String,
    pub pr_count: u8,
    pub show_list: bool,
    pub show_github: bool,
    pub show_azure: bool,
    pub show_review_state: bool,
}

impl Default for PrBoxSettings {
    fn default() -> Self {
        Self {
            enabled: false,
            size: WidgetSize::Medium,
            azure_account_id: String::new(),
            pr_count: 6,
            show_list: true,
            show_github: true,
            show_azure: true,
            show_review_state: true,
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
#[serde(rename_all = "camelCase")]
pub struct WindowPosition {
    pub x: i32,
    pub y: i32,
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
    fn a_file_without_a_schema_version_migrates_to_one() {
        let parsed: Settings = serde_json::from_str("{}").expect("parse");
        assert_eq!(parsed.schema_version, 1);
        assert_eq!(parsed.surface_mode, SurfaceMode::Auto);
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
        assert!(parsed.positions.is_empty());
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
    fn dragged_positions_round_trip() {
        let (_tmp, paths) = temp_paths();
        let mut settings = Settings::default();
        settings
            .positions
            .insert("LiveBox".into(), WindowPosition { x: 120, y: 340 });
        settings.save(&paths).expect("save");
        let loaded = Settings::load(&paths);
        assert_eq!(
            loaded.positions.get("LiveBox"),
            Some(&WindowPosition { x: 120, y: 340 })
        );
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
    fn azure_account_resolution_uses_the_selected_account_or_legacy_fields() {
        let mut settings = Settings::default();
        settings.tasks.organization = "legacy".into();
        settings.tasks.project = "legacy-project".into();
        assert_eq!(
            settings.azure_account(""),
            ("azure", "legacy", "legacy-project")
        );
        settings.azure_accounts.push(AzureAccount {
            id: "azure:work".into(),
            label: "Work".into(),
            organization: "work-org".into(),
            project: "work-project".into(),
        });
        assert_eq!(
            settings.azure_account("azure:work"),
            ("azure:work", "work-org", "work-project")
        );
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

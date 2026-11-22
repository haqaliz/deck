use std::fs;
use std::path::{Path, PathBuf};

use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Battery {
    pub name: String,
    pub percent: f64,
    pub status: String,
    pub minutes_left: Option<u64>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Accessory {
    pub name: String,
    pub percent: Option<f64>,
    pub detail: String,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct BatterySnapshot {
    pub written_at: String,
    pub ac_online: Option<bool>,
    pub batteries: Vec<Battery>,
    pub accessories: Vec<Accessory>,
}

pub fn load() -> BatterySnapshot {
    read_from(Path::new("/sys/class/power_supply")).unwrap_or_else(|_| empty())
}

pub fn read_from(root: &Path) -> std::io::Result<BatterySnapshot> {
    let mut batteries = Vec::new();
    let mut accessories = Vec::new();
    let mut ac_online = None;
    let entries = match fs::read_dir(root) {
        Ok(entries) => entries,
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => {
            return Ok(empty());
        }
        Err(error) => return Err(error),
    };
    let mut paths: Vec<PathBuf> = entries.flatten().map(|entry| entry.path()).collect();
    paths.sort();
    for path in paths {
        let name = path
            .file_name()
            .map(|name| name.to_string_lossy().into_owned())
            .unwrap_or_default();
        let kind = read_trim(&path.join("type")).unwrap_or_default();
        if kind.to_ascii_lowercase().contains("battery") {
            let scope = read_trim(&path.join("scope")).unwrap_or_default();
            let is_accessory = scope.eq_ignore_ascii_case("Device")
                || name.starts_with("hid-")
                || name.starts_with("hidpp");
            if is_accessory {
                if let Some(accessory) = read_accessory(&path, name) {
                    accessories.push(accessory);
                }
            } else if let Some(battery) = read_battery(&path, name) {
                batteries.push(battery);
            }
        } else if matches!(kind.as_str(), "Mains" | "USB" | "USB_C") {
            let online = read_trim(&path.join("online"))
                .and_then(|value| value.parse::<u8>().ok())
                .map(|value| value > 0);
            ac_online = match (ac_online, online) {
                (Some(existing), Some(current)) => Some(existing || current),
                (None, current) => current,
                (existing, None) => existing,
            };
        }
    }
    Ok(BatterySnapshot {
        written_at: chrono::Utc::now().to_rfc3339(),
        ac_online,
        batteries,
        accessories,
    })
}

fn empty() -> BatterySnapshot {
    BatterySnapshot {
        written_at: chrono::Utc::now().to_rfc3339(),
        ac_online: None,
        batteries: Vec::new(),
        accessories: Vec::new(),
    }
}

fn read_accessory(path: &Path, name: String) -> Option<Accessory> {
    let percent = read_number(&path.join("capacity"));
    let model = read_trim(&path.join("model_name"))
        .or_else(|| read_trim(&path.join("manufacturer")))
        .unwrap_or(name);
    let status = read_trim(&path.join("status")).unwrap_or_default();
    let detail = if status.is_empty() {
        "Bluetooth".into()
    } else {
        status
    };
    Some(Accessory {
        name: model,
        percent,
        detail,
    })
}

fn read_battery(path: &Path, name: String) -> Option<Battery> {
    let percent = read_number(&path.join("capacity"))?;
    let status = read_trim(&path.join("status")).unwrap_or_else(|| "Unknown".into());
    let minutes_left = read_number(&path.join("time_to_empty_now"))
        .map(|seconds| (seconds / 60.0).round() as u64)
        .or_else(|| {
            let energy = read_number(&path.join("energy_now"))?;
            let power = read_number(&path.join("power_now"))?;
            (power > 0.0).then(|| (energy / power * 60.0).round() as u64)
        })
        .or_else(|| {
            let charge = read_number(&path.join("charge_now"))?;
            let current = read_number(&path.join("current_now"))?;
            (current > 0.0).then(|| (charge / current * 60.0).round() as u64)
        });
    Some(Battery {
        name,
        percent: percent.clamp(0.0, 100.0),
        status,
        minutes_left,
    })
}

fn read_trim(path: &Path) -> Option<String> {
    fs::read_to_string(path)
        .ok()
        .map(|value| value.trim().to_string())
        .filter(|value| !value.is_empty())
}

fn read_number(path: &Path) -> Option<f64> {
    read_trim(path)?.parse::<f64>().ok()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reads_battery_and_ac_state_from_a_fixture() {
        let tmp = tempfile::tempdir().expect("temp");
        let bat = tmp.path().join("BAT0");
        let ac = tmp.path().join("AC");
        fs::create_dir_all(&bat).expect("bat");
        fs::create_dir_all(&ac).expect("ac");
        fs::write(bat.join("type"), "Battery\n").expect("type");
        fs::write(bat.join("capacity"), "72\n").expect("capacity");
        fs::write(bat.join("status"), "Discharging\n").expect("status");
        fs::write(bat.join("energy_now"), "36\n").expect("energy");
        fs::write(bat.join("power_now"), "6\n").expect("power");
        fs::write(ac.join("type"), "Mains\n").expect("ac type");
        fs::write(ac.join("online"), "0\n").expect("online");
        let mouse = tmp.path().join("hid-aa-bb");
        fs::create_dir_all(&mouse).expect("mouse");
        fs::write(mouse.join("type"), "Battery\n").expect("mouse type");
        fs::write(mouse.join("scope"), "Device\n").expect("scope");
        fs::write(mouse.join("capacity"), "58\n").expect("mouse capacity");
        fs::write(mouse.join("model_name"), "MX Master 3S\n").expect("model");
        let snapshot = read_from(tmp.path()).expect("snapshot");
        assert_eq!(snapshot.ac_online, Some(false));
        assert_eq!(snapshot.batteries.len(), 1);
        assert_eq!(snapshot.batteries[0].percent, 72.0);
        assert_eq!(snapshot.batteries[0].minutes_left, Some(360));
        assert_eq!(snapshot.accessories[0].name, "MX Master 3S");
        assert_eq!(snapshot.accessories[0].percent, Some(58.0));
    }

    #[test]
    fn missing_root_is_an_empty_snapshot() {
        let tmp = tempfile::tempdir().expect("temp");
        let snapshot = read_from(&tmp.path().join("missing")).expect("snapshot");
        assert!(snapshot.batteries.is_empty());
        assert_eq!(snapshot.ac_online, None);
    }
}

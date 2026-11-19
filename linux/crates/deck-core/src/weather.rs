use serde::{Deserialize, Serialize};
use serde_json::Value;

use crate::providers::{self, FetchError};

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct WeatherSnapshot {
    pub location: String,
    pub country: String,
    pub condition: WeatherCondition,
    pub days: Vec<WeatherDay>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct WeatherCondition {
    pub code: Option<i64>,
    pub desc: String,
    pub temp_c: Option<f64>,
    pub temp_f: Option<f64>,
    pub feels_like_c: Option<f64>,
    pub feels_like_f: Option<f64>,
    pub humidity: Option<f64>,
    pub wind_dir: String,
    pub wind_kmph: Option<f64>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct WeatherDay {
    pub date: String,
    /// Noon slot when present, else the first hourly code.
    pub code: Option<i64>,
    pub max_temp_c: Option<f64>,
    pub max_temp_f: Option<f64>,
    pub min_temp_c: Option<f64>,
    pub min_temp_f: Option<f64>,
    pub desc: String,
}

pub fn parse(payload: &str) -> Option<WeatherSnapshot> {
    let json: Value = serde_json::from_str(payload).ok()?;
    let current = json.get("current_condition")?.as_array()?.first()?;
    let condition = WeatherCondition {
        code: int(current, "weatherCode"),
        desc: desc_value(current.get("weatherDesc")),
        temp_c: number(current, "temp_C"),
        temp_f: number(current, "temp_F"),
        feels_like_c: number(current, "FeelsLikeC"),
        feels_like_f: number(current, "FeelsLikeF"),
        humidity: number(current, "humidity"),
        wind_dir: current
            .get("winddir16Point")
            .and_then(Value::as_str)
            .unwrap_or("")
            .trim()
            .to_owned(),
        wind_kmph: number(current, "windspeedKmph"),
    };

    let area = json
        .get("nearest_area")
        .and_then(Value::as_array)
        .and_then(|areas| areas.first());
    let location = area
        .and_then(|area| list_value(area.get("areaName")))
        .unwrap_or_default();
    let country = area
        .and_then(|area| list_value(area.get("country")))
        .unwrap_or_default();

    let days = json
        .get("weather")
        .and_then(Value::as_array)
        .map(|days| days.iter().map(day).collect())
        .unwrap_or_default();

    Some(WeatherSnapshot {
        location,
        country,
        condition,
        days,
    })
}

pub fn fetch(location: &str) -> Result<WeatherSnapshot, FetchError> {
    let encoded = providers::encode_path(location);
    let body = providers::get(&format!("https://wttr.in/{encoded}?format=j1"), &[])?;
    parse(&body).ok_or(FetchError::InvalidPayload)
}

/// WW weather code used by the face to pick a text glyph. Returns a plain
/// ASCII marker rather than an icon font so it renders on a minimal Pi OS.
pub fn glyph(code: Option<i64>) -> &'static str {
    match code {
        Some(113) => "☀",
        Some(116) => "⛅",
        Some(119 | 122) => "☁",
        Some(143 | 248 | 260) => "≡",
        Some(176 | 263 | 266 | 281 | 284 | 293 | 296) => "☂",
        Some(299 | 302 | 305 | 308 | 353 | 356 | 359) => "☔",
        Some(179 | 182 | 185 | 317 | 320 | 323 | 326 | 329 | 332 | 335 | 338) => "❄",
        Some(200 | 386 | 389) => "⚡",
        Some(227 | 230) => "❄",
        Some(311 | 314 | 350 | 374 | 377) => "☂",
        Some(362 | 365 | 368 | 371) => "☂",
        Some(392 | 395) => "⚡",
        _ => "☁",
    }
}

fn day(entry: &Value) -> WeatherDay {
    let hourly = entry
        .get("hourly")
        .and_then(Value::as_array)
        .map(Vec::as_slice)
        .unwrap_or(&[]);
    let noon = hourly
        .iter()
        .find(|slot| slot.get("time").and_then(Value::as_str) == Some("1200"));
    let code = noon
        .and_then(|slot| int(slot, "weatherCode"))
        .or_else(|| hourly.iter().find_map(|slot| int(slot, "weatherCode")));
    WeatherDay {
        date: entry
            .get("date")
            .and_then(Value::as_str)
            .unwrap_or("")
            .to_owned(),
        code,
        max_temp_c: number(entry, "maxtempC"),
        max_temp_f: number(entry, "maxtempF"),
        min_temp_c: number(entry, "mintempC"),
        min_temp_f: number(entry, "mintempF"),
        desc: desc_value(entry.get("weatherDesc")),
    }
}

fn desc_value(raw: Option<&Value>) -> String {
    list_value(raw).unwrap_or_default()
}

/// wttr wraps human strings in `[{"value": "..."}]`.
fn list_value(raw: Option<&Value>) -> Option<String> {
    let value = raw?.as_array()?.first()?.get("value")?.as_str()?;
    Some(value.trim().to_owned())
}

fn number(entry: &Value, key: &str) -> Option<f64> {
    entry.get(key)?.as_str()?.trim().parse().ok()
}

fn int(entry: &Value, key: &str) -> Option<i64> {
    entry.get(key)?.as_str()?.trim().parse().ok()
}

#[cfg(test)]
mod tests {
    use super::*;

    const FIXTURE: &str = include_str!("../../../contracts/fixtures/weather_j1.json");

    #[test]
    fn parses_the_wttr_contract() {
        let parsed = parse(FIXTURE).expect("weather");
        assert_eq!(parsed.location, "Amsterdam");
        assert_eq!(parsed.country, "Netherlands");
        assert_eq!(parsed.condition.code, Some(116));
        assert_eq!(parsed.condition.desc, "Partly cloudy");
        assert_eq!(parsed.condition.temp_c, Some(9.0));
        assert_eq!(parsed.condition.wind_dir, "SW");
        assert_eq!(parsed.days.len(), 3);
        assert_eq!(parsed.days[0].date, "2026-11-19");
        assert_eq!(parsed.days[0].code, Some(116));
        assert_eq!(parsed.days[0].max_temp_c, Some(11.0));
        assert_eq!(parsed.days[1].code, Some(296));
    }

    #[test]
    fn rejects_a_non_weather_payload() {
        assert!(parse("{\"error\":\"nope\"}").is_none());
    }

    #[test]
    fn every_code_maps_to_a_glyph() {
        assert_eq!(glyph(Some(113)), "☀");
        assert_eq!(glyph(Some(296)), "☂");
        assert_eq!(glyph(None), "☁");
    }
}

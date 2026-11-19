use chrono::{DateTime, Local, NaiveDate, Offset, Utc};
use chrono_tz::Tz;

/// The reference clock is always the machine's local zone; a row can be local
/// or any IANA zone.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Zone {
    Local,
    Named(Tz),
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ClockRow {
    pub id: String,
    pub name: String,
    pub time: String,
    /// "Yesterday", "Today" or "Tomorrow" relative to the reference zone.
    pub day: String,
    pub offset: String,
}

pub const LOCAL_ID: &str = "local";

pub fn now() -> DateTime<Utc> {
    Utc::now()
}

pub fn resolve(id: &str) -> Option<Zone> {
    let id = id.trim();
    if id.is_empty() {
        return None;
    }
    if id == LOCAL_ID {
        return Some(Zone::Local);
    }
    id.parse::<Tz>().ok().map(Zone::Named)
}

pub fn display_name(id: &str) -> String {
    let id = id.trim();
    if id == LOCAL_ID {
        return "Local".into();
    }
    let short = match id {
        "America/New_York" => "New York",
        "America/Los_Angeles" => "Los Angeles",
        "America/Mexico_City" => "Mexico City",
        "America/Argentina/Buenos_Aires" => "Buenos Aires",
        "America/Sao_Paulo" => "São Paulo",
        "Europe/Amsterdam" => "Amsterdam",
        "Europe/London" => "London",
        "Asia/Kathmandu" => "Kathmandu",
        "Asia/Tokyo" => "Tokyo",
        "Asia/Shanghai" => "Shanghai",
        "Asia/Kolkata" => "Kolkata",
        "Australia/Sydney" => "Sydney",
        "Pacific/Auckland" => "Auckland",
        other => other.split('/').next_back().unwrap_or(other),
    };
    short.replace('_', " ")
}

pub fn time_label(zone: Zone, now: DateTime<Utc>) -> String {
    match zone {
        Zone::Local => now.with_timezone(&Local).format("%H:%M").to_string(),
        Zone::Named(tz) => now.with_timezone(&tz).format("%H:%M").to_string(),
    }
}

pub fn offset_seconds(zone: Zone, now: DateTime<Utc>) -> i32 {
    match zone {
        Zone::Local => now.with_timezone(&Local).offset().fix().local_minus_utc(),
        Zone::Named(tz) => now.with_timezone(&tz).offset().fix().local_minus_utc(),
    }
}

pub fn date(zone: Zone, now: DateTime<Utc>) -> NaiveDate {
    match zone {
        Zone::Local => now.with_timezone(&Local).date_naive(),
        Zone::Named(tz) => now.with_timezone(&tz).date_naive(),
    }
}

/// "+0HRS", "+1:00", "-3:30" — minutes are never rounded.
pub fn offset_label(zone: Zone, reference: Zone, now: DateTime<Utc>) -> String {
    let delta = offset_seconds(zone, now) - offset_seconds(reference, now);
    if delta == 0 {
        return "+0HRS".into();
    }
    let sign = if delta < 0 { "-" } else { "+" };
    let magnitude = delta.unsigned_abs();
    format!("{sign}{}:{:02}", magnitude / 3600, (magnitude % 3600) / 60)
}

pub fn relative_day(zone: Zone, reference: Zone, now: DateTime<Utc>) -> String {
    match date(zone, now).cmp(&date(reference, now)) {
        std::cmp::Ordering::Less => "Yesterday".into(),
        std::cmp::Ordering::Equal => "Today".into(),
        std::cmp::Ordering::Greater => "Tomorrow".into(),
    }
}

pub fn rows(ids: &[String], reference: Zone, now: DateTime<Utc>, limit: usize) -> Vec<ClockRow> {
    let mut rows = Vec::new();
    for id in ids {
        if rows.len() >= limit {
            break;
        }
        let Some(zone) = resolve(id) else {
            continue;
        };
        rows.push(ClockRow {
            id: id.clone(),
            name: display_name(id),
            time: time_label(zone, now),
            day: relative_day(zone, reference, now),
            offset: offset_label(zone, reference, now),
        });
    }
    rows
}

/// Explicit preference wins when it still resolves; otherwise the first
/// non-local city (a small face showing your own zone at +0HRS says nothing).
pub fn main_city_id(ids: &[String], preferred: &str) -> Option<String> {
    let valid: Vec<&String> = ids.iter().filter(|id| resolve(id).is_some()).collect();
    if !preferred.trim().is_empty() {
        if let Some(found) = valid.iter().find(|id| id.as_str() == preferred.trim()) {
            return Some((*found).clone());
        }
    }
    valid
        .iter()
        .find(|id| id.trim() != LOCAL_ID)
        .or_else(|| valid.first())
        .map(|id| (*id).clone())
}

#[cfg(test)]
mod tests {
    use super::*;
    use chrono::TimeZone;

    fn utc() -> Zone {
        Zone::Named(chrono_tz::UTC)
    }

    fn at(hour: u32, minute: u32) -> DateTime<Utc> {
        Utc.with_ymd_and_hms(2026, 1, 15, hour, minute, 0)
            .single()
            .expect("date")
    }

    #[test]
    fn resolves_local_iana_and_rejects_junk() {
        assert_eq!(resolve("local"), Some(Zone::Local));
        assert_eq!(
            resolve("Europe/Amsterdam"),
            Some(Zone::Named(chrono_tz::Europe::Amsterdam))
        );
        assert_eq!(resolve("Not/AZone"), None);
        assert_eq!(resolve(""), None);
    }

    #[test]
    fn names_use_the_curated_short_form() {
        assert_eq!(display_name("America/New_York"), "New York");
        assert_eq!(
            display_name("America/Argentina/Buenos_Aires"),
            "Buenos Aires"
        );
        assert_eq!(display_name("Pacific/Chatham"), "Chatham");
        assert_eq!(display_name("local"), "Local");
    }

    #[test]
    fn times_and_offsets_follow_the_zone() {
        let now = at(12, 0);
        let amsterdam = resolve("Europe/Amsterdam").expect("zone");
        assert_eq!(time_label(amsterdam, now), "13:00");
        assert_eq!(offset_label(amsterdam, utc(), now), "+1:00");

        let kathmandu = resolve("Asia/Kathmandu").expect("zone");
        assert_eq!(offset_label(kathmandu, utc(), now), "+5:45");
        assert_eq!(offset_label(utc(), utc(), now), "+0HRS");

        let new_york = resolve("America/New_York").expect("zone");
        assert_eq!(time_label(new_york, now), "07:00");
        assert_eq!(offset_label(new_york, utc(), now), "-5:00");
    }

    #[test]
    fn relative_day_crosses_midnight() {
        let now = at(23, 30);
        assert_eq!(
            relative_day(resolve("Asia/Tokyo").expect("tokyo"), utc(), now),
            "Tomorrow"
        );
        assert_eq!(
            relative_day(resolve("America/Los_Angeles").expect("la"), utc(), now),
            "Today"
        );

        let early = at(1, 0);
        assert_eq!(
            relative_day(resolve("Pacific/Honolulu").expect("hnl"), utc(), early),
            "Yesterday"
        );
    }

    #[test]
    fn rows_keep_order_skip_junk_and_cap() {
        let ids = vec![
            "UTC".to_string(),
            "Not/AZone".to_string(),
            "Asia/Tokyo".to_string(),
            "Europe/Amsterdam".to_string(),
        ];
        let rows = rows(&ids, utc(), at(12, 0), 2);
        assert_eq!(rows.len(), 2);
        assert_eq!(rows[0].id, "UTC");
        assert_eq!(rows[0].time, "12:00");
        assert_eq!(rows[1].name, "Tokyo");
    }

    #[test]
    fn main_city_prefers_an_explicit_valid_choice_then_non_local() {
        let ids = vec![
            "local".to_string(),
            "UTC".to_string(),
            "Asia/Tokyo".to_string(),
        ];
        assert_eq!(
            main_city_id(&ids, "Asia/Tokyo").as_deref(),
            Some("Asia/Tokyo")
        );
        assert_eq!(main_city_id(&ids, "Europe/Paris").as_deref(), Some("UTC"));
        assert_eq!(main_city_id(&ids, "local").as_deref(), Some("local"));
    }
}

use chrono::{DateTime, Local, NaiveDate, NaiveDateTime, TimeZone, Utc};
use serde::{Deserialize, Serialize};

use crate::providers::{self, FetchError};

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct CalEvent {
    pub id: String,
    pub title: String,
    pub start: String,
    pub end: String,
    pub is_all_day: bool,
    pub calendar_title: String,
    pub calendar_id: String,
    pub color: String,
    pub url: String,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct CalBoxSnapshot {
    pub written_at: String,
    pub events: Vec<CalEvent>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
struct CalendarRef {
    href: String,
    title: String,
    color: String,
}

const PALETTE: [&str; 6] = [
    "#0a84ff", "#30d158", "#ff9f0a", "#ff375f", "#bf5af2", "#40c8e0",
];

/// Reads every VEVENT calendar on a CalDAV server for a today/tomorrow
/// horizon. The server is asked to expand recurrence rules; servers that
/// reject `expand` are retried without it and show the master occurrences.
pub fn fetch(
    server_url: &str,
    username: &str,
    password: &str,
) -> Result<CalBoxSnapshot, FetchError> {
    let base = providers::normalize_base(server_url).ok_or(FetchError::NotConfigured)?;
    if username.trim().is_empty() || password.is_empty() {
        return Err(FetchError::NotConfigured);
    }
    let auth = providers::basic_auth(username.trim(), password);
    let calendars = discover_calendars(&base, &auth)?;
    let now = Utc::now();
    let start = (now - chrono::Duration::days(1))
        .format("%Y%m%dT%H%M%SZ")
        .to_string();
    let end = (now + chrono::Duration::days(3))
        .format("%Y%m%dT%H%M%SZ")
        .to_string();
    let mut events = Vec::new();
    for calendar in &calendars {
        match report_events(calendar, &auth, &start, &end, true) {
            Ok(mut calendar_events) => events.append(&mut calendar_events),
            Err(FetchError::BadResponse(_)) => {
                let mut fallback = report_events(calendar, &auth, &start, &end, false)?;
                events.append(&mut fallback);
            }
            Err(error) => return Err(error),
        }
        // A calendar with no events is still a successful response.
    }
    events.sort_by(|left, right| {
        left.start
            .cmp(&right.start)
            .then_with(|| left.title.cmp(&right.title))
    });
    Ok(CalBoxSnapshot {
        written_at: Utc::now().to_rfc3339(),
        events,
    })
}

/// One PROPFIND, used by the Credentials Verify button.
pub fn probe(server_url: &str, username: &str, password: &str) -> Result<usize, FetchError> {
    let base = providers::normalize_base(server_url).ok_or(FetchError::NotConfigured)?;
    if username.trim().is_empty() || password.is_empty() {
        return Err(FetchError::NotConfigured);
    }
    let auth = providers::basic_auth(username.trim(), password);
    Ok(discover_calendars(&base, &auth)?.len())
}

fn discover_calendars(base: &str, auth: &str) -> Result<Vec<CalendarRef>, FetchError> {
    let body = r#"<?xml version="1.0" encoding="utf-8"?>
<d:propfind xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav" xmlns:ical="http://apple.com/ns/ical/">
  <d:prop><d:resourcetype/><d:displayname/><ical:calendar-color/><c:supported-calendar-component-set/></d:prop>
</d:propfind>"#;
    let response = providers::request(
        "PROPFIND",
        base,
        &[
            ("Authorization", auth),
            ("Depth", "1"),
            ("Content-Type", "application/xml; charset=utf-8"),
        ],
        Some(body),
    );
    let body = match response {
        Ok(body) => body,
        Err(FetchError::BadResponse(_)) => {
            // Some servers only expose the calendar at the URL itself.
            return Ok(vec![CalendarRef {
                href: base.to_owned(),
                title: base.to_owned(),
                color: PALETTE[0].to_owned(),
            }]);
        }
        Err(error) => return Err(error),
    };
    let mut calendars = parse_calendars(&body, base);
    if calendars.is_empty() {
        calendars.push(CalendarRef {
            href: base.to_owned(),
            title: base.to_owned(),
            color: PALETTE[0].to_owned(),
        });
    }
    Ok(calendars)
}

fn parse_calendars(body: &str, base: &str) -> Vec<CalendarRef> {
    let Ok(document) = roxmltree::Document::parse(body) else {
        return Vec::new();
    };
    let mut out = Vec::new();
    for response in document
        .descendants()
        .filter(|node| node.tag_name().name() == "response")
    {
        let Some(href) = response
            .descendants()
            .find(|node| node.tag_name().name() == "href")
            .and_then(|node| node.text())
        else {
            continue;
        };
        let is_calendar = response
            .descendants()
            .find(|node| node.tag_name().name() == "resourcetype")
            .map(|node| {
                node.descendants()
                    .any(|child| child.tag_name().name() == "calendar")
            })
            .unwrap_or(false);
        if !is_calendar {
            continue;
        }
        let supports_events = response
            .descendants()
            .find(|node| node.tag_name().name() == "supported-calendar-component-set")
            .map(|node| {
                node.descendants()
                    .any(|child| child.attribute("name") == Some("VEVENT"))
            })
            .unwrap_or(true);
        if !supports_events {
            continue;
        }
        let title = response
            .descendants()
            .find(|node| node.tag_name().name() == "displayname")
            .and_then(|node| node.text())
            .filter(|title| !title.trim().is_empty())
            .unwrap_or("Calendar")
            .trim()
            .to_owned();
        let color = response
            .descendants()
            .find(|node| node.tag_name().name() == "calendar-color")
            .and_then(|node| node.text())
            .map(normalize_color)
            .unwrap_or_else(|| PALETTE[out.len() % PALETTE.len()].to_owned());
        out.push(CalendarRef {
            href: resolve_url(base, href.trim()),
            title,
            color,
        });
    }
    out
}

fn normalize_color(raw: &str) -> String {
    let raw = raw.trim();
    let hex = raw.strip_prefix('#').unwrap_or(raw);
    match hex.get(..6) {
        Some(hex) if hex.chars().all(|c| c.is_ascii_hexdigit()) => format!("#{hex}"),
        _ => PALETTE[0].to_owned(),
    }
}

fn resolve_url(base: &str, href: &str) -> String {
    if href.starts_with("http://") || href.starts_with("https://") {
        return href.to_owned();
    }
    if let Some(rest) = href.strip_prefix('/') {
        if let Some((scheme, after)) = base.split_once("://") {
            let host = after.split('/').next().unwrap_or(after);
            return format!("{scheme}://{host}/{rest}");
        }
    }
    format!(
        "{}/{}",
        base.trim_end_matches('/'),
        href.trim_start_matches('/')
    )
}

fn report_events(
    calendar: &CalendarRef,
    auth: &str,
    start: &str,
    end: &str,
    expand: bool,
) -> Result<Vec<CalEvent>, FetchError> {
    let calendar_data = if expand {
        format!("<c:calendar-data><c:expand start=\"{start}\" end=\"{end}\"/></c:calendar-data>")
    } else {
        "<c:calendar-data/>".to_owned()
    };
    let body = format!(
        r#"<?xml version="1.0" encoding="utf-8"?>
<c:calendar-query xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav">
  <d:prop><d:getetag/>{calendar_data}</d:prop>
  <c:filter><c:comp-filter name="VCALENDAR"><c:comp-filter name="VEVENT"><c:time-range start="{start}" end="{end}"/></c:comp-filter></c:comp-filter></c:filter>
</c:calendar-query>"#
    );
    let response = providers::request(
        "REPORT",
        &calendar.href,
        &[
            ("Authorization", auth),
            ("Depth", "1"),
            ("Content-Type", "application/xml; charset=utf-8"),
        ],
        Some(&body),
    )?;
    Ok(parse_calendar_report(&response, calendar))
}

fn parse_calendar_report(body: &str, calendar: &CalendarRef) -> Vec<CalEvent> {
    let Ok(document) = roxmltree::Document::parse(body) else {
        return Vec::new();
    };
    let mut out = Vec::new();
    for data in document
        .descendants()
        .filter(|node| node.tag_name().name() == "calendar-data")
    {
        let Some(ics) = data.text() else {
            continue;
        };
        out.extend(parse_ics(ics, calendar));
    }
    out
}

fn parse_ics(ics: &str, calendar: &CalendarRef) -> Vec<CalEvent> {
    let lines = unfold(ics);
    let mut events = Vec::new();
    let mut fields: Vec<(String, String)> = Vec::new();
    let mut in_event = false;
    for line in lines {
        let upper = line.to_uppercase();
        if upper.starts_with("BEGIN:VEVENT") {
            in_event = true;
            fields.clear();
            continue;
        }
        if upper.starts_with("END:VEVENT") {
            if in_event {
                if let Some(event) = build_event(&fields, calendar) {
                    events.push(event);
                }
            }
            in_event = false;
            continue;
        }
        if !in_event {
            continue;
        }
        if let Some((key, value)) = line.split_once(':') {
            let key = key.split(';').next().unwrap_or(key).to_uppercase();
            fields.push((key, value.to_owned()));
        }
    }
    events
}

fn unfold(ics: &str) -> Vec<String> {
    let mut lines: Vec<String> = Vec::new();
    for raw in ics.replace("\r\n", "\n").split('\n') {
        if (raw.starts_with(' ') || raw.starts_with('\t')) && !lines.is_empty() {
            if let Some(last) = lines.last_mut() {
                last.push_str(&raw[1..]);
            }
        } else if !raw.is_empty() {
            lines.push(raw.to_owned());
        }
    }
    lines
}

fn build_event(fields: &[(String, String)], calendar: &CalendarRef) -> Option<CalEvent> {
    let get = |name: &str| {
        fields
            .iter()
            .find(|(key, _)| key == name)
            .map(|(_, value)| value.as_str())
    };
    if get("STATUS").map(|status| status.eq_ignore_ascii_case("CANCELLED")) == Some(true) {
        return None;
    }
    let title = unescape(get("SUMMARY").unwrap_or("Untitled"));
    let (start, is_all_day) = parse_datetime(get("DTSTART")?)?;
    let end = get("DTEND")
        .and_then(parse_datetime)
        .map(|(end, _)| end)
        .unwrap_or_else(|| {
            if is_all_day {
                start + chrono::Duration::days(1)
            } else {
                start + chrono::Duration::hours(1)
            }
        });
    if end <= start {
        return None;
    }
    let uid = get("UID")
        .map(str::to_owned)
        .unwrap_or_else(|| format!("{title}:{start}"));
    let id = format!("{uid}@{}", start.timestamp());
    Some(CalEvent {
        id,
        title,
        start: start.to_rfc3339(),
        end: end.to_rfc3339(),
        is_all_day,
        calendar_title: calendar.title.clone(),
        calendar_id: calendar.href.clone(),
        color: calendar.color.clone(),
        url: normalize_event_url(get("URL").unwrap_or("")),
    })
}

fn parse_datetime(value: &str) -> Option<(DateTime<Utc>, bool)> {
    let value = value.trim();
    if value.len() == 8 {
        let date = NaiveDate::parse_from_str(value, "%Y%m%d").ok()?;
        let local = Local
            .from_local_datetime(&date.and_hms_opt(0, 0, 0)?)
            .single()?;
        return Some((local.with_timezone(&Utc), true));
    }
    if let Ok(value) = NaiveDateTime::parse_from_str(value, "%Y%m%dT%H%M%SZ") {
        return Some((value.and_utc(), false));
    }
    if let Ok(value) = NaiveDateTime::parse_from_str(value, "%Y%m%dT%H%M%S") {
        let local = Local.from_local_datetime(&value).single()?;
        return Some((local.with_timezone(&Utc), false));
    }
    None
}

fn normalize_event_url(raw: &str) -> String {
    let raw = raw.trim();
    (raw.starts_with("https://") || raw.starts_with("http://"))
        .then(|| raw.to_owned())
        .unwrap_or_default()
}

fn unescape(value: &str) -> String {
    value
        .replace("\\n", "\n")
        .replace("\\N", "\n")
        .replace("\\,", ",")
        .replace("\\;", ";")
        .replace("\\\\", "\\")
        .trim()
        .to_owned()
}

#[cfg(test)]
mod tests {
    use super::*;

    const ICS: &str = "BEGIN:VCALENDAR\r\nBEGIN:VEVENT\r\nUID:one\r\nSUMMARY:Design review\\, with Sam\r\nDTSTART:20261122T090000Z\r\nDTEND:20261122T100000Z\r\nURL:https://meet.example.com/abc\r\nEND:VEVENT\r\nBEGIN:VEVENT\r\nUID:two\r\nSUMMARY:Holiday\r\nDTSTART;VALUE=DATE:20261122\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n";

    #[test]
    fn parses_timed_and_all_day_events() {
        let calendar = CalendarRef {
            href: "https://cal.example.com/work/".into(),
            title: "Work".into(),
            color: "#0a84ff".into(),
        };
        let events = parse_ics(ICS, &calendar);
        assert_eq!(events.len(), 2);
        assert_eq!(events[0].title, "Design review, with Sam");
        assert!(!events[0].is_all_day);
        assert_eq!(events[0].url, "https://meet.example.com/abc");
        assert!(events[1].is_all_day);
        assert_eq!(events[1].calendar_title, "Work");
        assert!(events[1].end > events[1].start);
    }

    #[test]
    fn parses_calendar_multistatus_and_colors() {
        let xml = r#"<?xml version="1.0"?>
<d:multistatus xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav" xmlns:ical="http://apple.com/ns/ical/">
 <d:response>
  <d:href>/cal/work/</d:href>
  <d:propstat><d:prop>
   <d:resourcetype><d:collection/><c:calendar/></d:resourcetype>
   <d:displayname>Work</d:displayname>
   <ical:calendar-color>#FF2968FF</ical:calendar-color>
   <c:supported-calendar-component-set><c:comp name="VEVENT"/></c:supported-calendar-component-set>
  </d:prop></d:propstat>
 </d:response>
</d:multistatus>"#;
        let calendars = parse_calendars(xml, "https://cal.example.com");
        assert_eq!(calendars.len(), 1);
        assert_eq!(calendars[0].href, "https://cal.example.com/cal/work/");
        assert_eq!(calendars[0].title, "Work");
        assert_eq!(calendars[0].color, "#FF2968");
    }

    #[test]
    fn resolves_relative_and_absolute_hrefs() {
        assert_eq!(
            resolve_url("https://cal.example.com/dav/", "/cal/work/"),
            "https://cal.example.com/cal/work/"
        );
        assert_eq!(
            resolve_url("https://cal.example.com/dav/", "work/"),
            "https://cal.example.com/dav/work/"
        );
    }
}

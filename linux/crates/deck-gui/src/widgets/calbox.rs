use std::cell::RefCell;
use std::rc::Rc;

use chrono::{DateTime, Duration, Local, TimeZone, Utc};
use deck_core::calbox::{CalBoxSnapshot, CalEvent};
use deck_core::paths::Paths;
use deck_core::settings::{Settings, WidgetSize};
use deck_core::snapshot;
use gtk4 as gtk;
use gtk4::prelude::*;

use crate::widgets::{self, feed};

pub fn build(
    app: &gtk::Application,
    settings: Rc<RefCell<Settings>>,
    paths: Paths,
) -> (gtk::ApplicationWindow, i32) {
    let size = settings.borrow().calbox.size;
    let feed = feed::build(app, "CalBox", size, (150, 240, 340), settings.clone());
    let body = feed.body.clone();
    let feed_size = feed.size;
    let paths_for_tick = paths.clone();
    let settings_for_tick = settings.clone();
    let tick = move || {
        let cal = settings_for_tick.borrow().calbox.clone();
        widgets::clear(&body);
        let Some(snapshot) = snapshot::read_payload::<CalBoxSnapshot>(&paths_for_tick, "calbox")
        else {
            widgets::add_row(&body, &widgets::status_text(&paths_for_tick, "calbox"));
            return gtk::glib::ControlFlow::Continue;
        };
        let now = Utc::now();
        let local_now = now.with_timezone(&Local);
        let start_today = local_now
            .date_naive()
            .and_hms_opt(0, 0, 0)
            .and_then(|value| Local.from_local_datetime(&value).single())
            .map(|value| value.with_timezone(&Utc))
            .unwrap_or(now);
        let start_tomorrow = start_today + Duration::days(1);
        let start_after = start_today + Duration::days(2);

        let mut events: Vec<(DateTime<Utc>, DateTime<Utc>, &CalEvent)> = snapshot
            .events
            .iter()
            .filter_map(|event| {
                let start = parse(&event.start)?;
                let end = parse(&event.end)?;
                (end > now).then_some((start, end, event))
            })
            .collect();
        events.sort_by(|left, right| {
            left.0
                .cmp(&right.0)
                .then_with(|| left.2.title.cmp(&right.2.title))
        });

        let all_day: Vec<_> = events
            .iter()
            .filter(|(start, _, event)| event.is_all_day && *start < start_tomorrow)
            .collect();
        let today: Vec<_> = events
            .iter()
            .filter(|(start, _, event)| !event.is_all_day && *start < start_tomorrow)
            .collect();
        let tomorrow: Vec<_> = events
            .iter()
            .filter(|(start, _, event)| {
                !event.is_all_day && *start >= start_tomorrow && *start < start_after
            })
            .collect();

        let today_limit = match feed_size {
            WidgetSize::Small => 3,
            _ => cal.today_count.max(1) as usize,
        };
        let tomorrow_limit = match feed_size {
            WidgetSize::Small => 2,
            WidgetSize::Medium => 4,
            WidgetSize::Large => cal.tomorrow_count.max(1) as usize,
        };

        if cal.show_today {
            widgets::section(&body, "TODAY");
            let all_day = if cal.show_all_day {
                all_day.as_slice()
            } else {
                &[]
            };
            section(
                &body,
                all_day,
                &today,
                today_limit,
                "Nothing left today",
                &cal,
            );
        }
        if cal.show_tomorrow {
            if cal.show_today {
                let divider = gtk::Separator::new(gtk::Orientation::Horizontal);
                divider.add_css_class("widget-divider");
                body.append(&divider);
            }
            widgets::section(&body, "TOMORROW");
            section(
                &body,
                &[],
                &tomorrow,
                tomorrow_limit,
                "Nothing scheduled",
                &cal,
            );
        }
        gtk::glib::ControlFlow::Continue
    };

    tick();
    gtk::glib::timeout_add_seconds_local(30, tick);
    (feed.window, feed.height)
}

fn section(
    body: &gtk::Box,
    all_day: &[&(DateTime<Utc>, DateTime<Utc>, &CalEvent)],
    timed: &[&(DateTime<Utc>, DateTime<Utc>, &CalEvent)],
    limit: usize,
    empty: &str,
    settings: &deck_core::settings::CalBoxSettings,
) {
    if all_day.is_empty() && timed.is_empty() {
        widgets::add_row(body, empty);
        return;
    }
    let mut shown = 0;
    for (_, _, event) in all_day {
        if shown >= limit {
            break;
        }
        add_row(body, event, "all-day", settings);
        shown += 1;
    }
    for (start, _, event) in timed {
        if shown >= limit {
            break;
        }
        add_row(
            body,
            event,
            &start.with_timezone(&Local).format("%H:%M").to_string(),
            settings,
        );
        shown += 1;
    }
    let hidden = all_day.len() + timed.len() - shown;
    if hidden > 0 {
        let label = gtk::Label::new(Some(&format!("+{hidden} more")));
        label.add_css_class("row-meta");
        label.set_halign(gtk::Align::Start);
        body.append(&label);
    }
}

fn add_row(
    body: &gtk::Box,
    event: &CalEvent,
    time: &str,
    settings: &deck_core::settings::CalBoxSettings,
) {
    let row = gtk::Box::new(gtk::Orientation::Horizontal, 6);
    let color = if settings.use_calendar_colors {
        event.color.as_str()
    } else {
        settings.accent_color.as_str()
    };
    row.append(&widgets::dot(color));
    let time = gtk::Label::new(Some(time));
    time.add_css_class("row-meta");
    time.set_width_chars(5);
    row.append(&time);
    if event.url.is_empty() {
        let title = gtk::Label::new(Some(&event.title));
        title.add_css_class("row-name");
        title.set_ellipsize(gtk::pango::EllipsizeMode::End);
        title.set_hexpand(true);
        title.set_xalign(0.0);
        row.append(&title);
    } else {
        let link = gtk::LinkButton::with_label(&event.url, &event.title);
        link.add_css_class("link-row");
        link.set_hexpand(true);
        link.set_halign(gtk::Align::Start);
        row.append(&link);
    }
    body.append(&row);
}

fn parse(value: &str) -> Option<DateTime<Utc>> {
    DateTime::parse_from_rfc3339(value)
        .ok()
        .map(|value| value.with_timezone(&Utc))
}

use std::cell::RefCell;
use std::rc::Rc;

use deck_core::logbox::LogBoxSnapshot;
use deck_core::paths::Paths;
use deck_core::settings::{LogTextMode, Settings, WidgetSize};
use deck_core::snapshot;
use gtk4 as gtk;
use gtk4::prelude::*;

use crate::widgets::{self, feed};

pub fn build(
    app: &gtk::Application,
    settings: Rc<RefCell<Settings>>,
    paths: Paths,
) -> (gtk::ApplicationWindow, i32) {
    let size = settings.borrow().logbox.size;
    let feed = feed::build(app, "Logs", size, (170, 280, 380));
    let body = feed.body.clone();
    let feed_size = feed.size;
    let paths_for_tick = paths.clone();
    let settings_for_tick = settings.clone();
    let tick = move || {
        let log = settings_for_tick.borrow().logbox.clone();
        widgets::clear(&body);
        let Some(snapshot) = snapshot::read_payload::<LogBoxSnapshot>(&paths_for_tick, "logbox")
        else {
            widgets::add_row(&body, &widgets::status_text(&paths_for_tick, "logbox"));
            return gtk::glib::ControlFlow::Continue;
        };

        let summary = gtk::Box::new(gtk::Orientation::Horizontal, 14);
        let errors = widgets::metric_label("ERR");
        errors.set_text(&format!("ERR  {}", snapshot.error_small));
        if snapshot.error_small > 0 {
            errors.add_css_class("alarm");
        }
        let warns = widgets::metric_label("WARN");
        warns.set_text(&format!("WARN  {}", snapshot.warn_small));
        if snapshot.warn_small > 0 {
            warns.add_css_class("warn");
        }
        summary.append(&errors);
        summary.append(&warns);
        body.append(&summary);

        if let Some(at) = snapshot.last_error_at.as_deref() {
            widgets::add_row(&body, &format!("last error {}", short_time(at)));
        }

        if log.show_trend && feed_size != WidgetSize::Small && !snapshot.trend.is_empty() {
            let chart = gtk::DrawingArea::new();
            chart.set_size_request(-1, 40);
            let values: Vec<i64> = snapshot
                .trend
                .iter()
                .map(|point| point.count as i64)
                .collect();
            chart.set_draw_func(move |_, cr, width, height| {
                widgets::draw_bars(cr, width, height, &values);
            });
            body.append(&chart);
        }

        if feed_size != WidgetSize::Small {
            widgets::section(&body, "SERVICES");
            for service in snapshot.services.iter().take(4) {
                widgets::add_row(
                    &body,
                    &format!("{}   {} errors", service.name, service.count),
                );
            }
            if snapshot.services.is_empty() {
                widgets::add_row(&body, "No errors in the window");
            }
        }

        if feed_size == WidgetSize::Large {
            widgets::section(&body, "TEMPLATES");
            for template in snapshot.templates.iter().take(4) {
                widgets::add_row(&body, &format!("{}   {}", template.name, template.count));
            }
            if snapshot.templates.is_empty() {
                widgets::add_row(&body, "None");
            }
        }

        if log.text_mode != LogTextMode::Templates && !snapshot.recent.is_empty() {
            widgets::section(&body, "RECENT");
            for line in snapshot.recent.iter().take(3) {
                widgets::add_row(
                    &body,
                    &format!(
                        "{}  {}  {}",
                        short_time(&line.at),
                        line.level.to_uppercase(),
                        line.message
                    ),
                );
            }
        }

        if let Some(base) = valid_base(&log.base_url) {
            widgets::link_row(&body, "Open Kibana", &format!("{base}/app/discover"));
        }
        if let Some(note) = &snapshot.note {
            widgets::add_row(&body, note);
        }
        gtk::glib::ControlFlow::Continue
    };

    tick();
    gtk::glib::timeout_add_seconds_local(5, tick);
    (feed.window, feed.height)
}

fn short_time(value: &str) -> &str {
    value.get(11..16).unwrap_or(value)
}

fn valid_base(base: &str) -> Option<String> {
    let base = base.trim().trim_end_matches('/');
    (base.starts_with("https://") || base.starts_with("http://")).then(|| base.to_owned())
}

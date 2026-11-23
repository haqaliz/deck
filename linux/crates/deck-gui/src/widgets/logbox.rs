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
    let feed = feed::build(app, "Logs", size, (170, 280, 380), settings.clone());
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

        let header = gtk::Box::new(gtk::Orientation::Horizontal, 6);
        let name = gtk::Label::new(None);
        name.set_markup(&format!(
            "<span foreground=\"#9a9aa1\">LOGBOX</span>  <span foreground=\"{}\">{}</span>",
            widgets::BLUE,
            snapshot.environment.to_uppercase()
        ));
        name.set_halign(gtk::Align::Start);
        header.append(&name);
        if let Some(at) = snapshot.last_error_at.as_deref() {
            let last = gtk::Label::new(Some(short_time(at)));
            last.add_css_class("row-meta");
            last.set_hexpand(true);
            last.set_xalign(1.0);
            header.append(&last);
        }
        body.append(&header);

        if feed_size == WidgetSize::Small {
            let summary = gtk::Box::new(gtk::Orientation::Horizontal, 14);
            let errors = widgets::metric_label("ERR");
            errors.set_markup(&widgets::metric_markup(
                "ERR",
                &snapshot.error_small.to_string(),
                widgets::RED,
                widgets::WHITE,
            ));
            let warns = widgets::metric_label("WARN");
            warns.set_markup(&widgets::metric_markup(
                "WARN",
                &snapshot.warn_small.to_string(),
                widgets::ORANGE,
                widgets::WHITE,
            ));
            summary.append(&errors);
            summary.append(&warns);
            body.append(&summary);
        } else {
            let numbers = gtk::Box::new(gtk::Orientation::Horizontal, 14);
            let errors = gtk::Label::new(Some(&snapshot.error_small.to_string()));
            errors.add_css_class("log-count");
            let errors_label =
                gtk::Label::new(Some(&format!("ERRORS · {}m", snapshot.small_minutes)));
            errors_label.add_css_class("row-meta");
            errors_label.set_xalign(0.0);
            let column = gtk::Box::new(gtk::Orientation::Vertical, 0);
            column.append(&errors);
            column.append(&errors_label);
            numbers.append(&column);
            let large = gtk::Label::new(Some(&snapshot.error_large.to_string()));
            large.add_css_class("row-title");
            let large_label =
                gtk::Label::new(Some(&format!("LAST {}h", snapshot.large_minutes / 60)));
            large_label.add_css_class("row-meta");
            large_label.set_xalign(0.0);
            let large_column = gtk::Box::new(gtk::Orientation::Vertical, 0);
            large_column.set_margin_top(6);
            large_column.append(&large);
            large_column.append(&large_label);
            numbers.append(&large_column);
            let warns = gtk::Label::new(None);
            warns.add_css_class("row-meta");
            warns.set_hexpand(true);
            warns.set_xalign(1.0);
            warns.set_markup(&format!(
                "<span foreground=\"#8e8e93\">{} WARN · {} IN {}h</span>",
                snapshot.warn_small,
                snapshot.warn_large,
                snapshot.large_minutes / 60
            ));
            numbers.append(&warns);
            body.append(&numbers);
        }

        if log.show_trend && feed_size != WidgetSize::Small && !snapshot.trend.is_empty() {
            let chart = gtk::DrawingArea::new();
            chart.set_size_request(-1, 48);
            let values: Vec<i64> = snapshot
                .trend
                .iter()
                .map(|point| point.count as i64)
                .collect();
            chart.set_draw_func(move |_, cr, width, height| {
                widgets::draw_trend_bars(cr, width, height, &values, widgets::ORANGE);
            });
            body.append(&chart);
        }

        if feed_size != WidgetSize::Small {
            widgets::section(&body, "SERVICES");
            for service in snapshot.services.iter().take(4) {
                let (_, _, count) = widgets::split_row(&body, &service.name);
                count.set_markup(&format!(
                    "<span foreground=\"#8e8e93\">{} errors</span>",
                    service.count
                ));
            }
            if snapshot.services.is_empty() {
                widgets::add_row(&body, "No errors in the window");
            }
        }

        if feed_size == WidgetSize::Large {
            widgets::section(&body, "TEMPLATES");
            for template in snapshot.templates.iter().take(4) {
                let (_, _, count) = widgets::split_row(&body, &template.name);
                count.set_markup(&format!(
                    "<span foreground=\"#8e8e93\">{}</span>",
                    template.count
                ));
            }
            if snapshot.templates.is_empty() {
                widgets::add_row(&body, "None");
            }
        }

        if log.text_mode != LogTextMode::Templates && !snapshot.recent.is_empty() {
            widgets::section(&body, "RECENT");
            for line in snapshot
                .recent
                .iter()
                .take(if feed_size == WidgetSize::Large { 5 } else { 3 })
            {
                let row = gtk::Box::new(gtk::Orientation::Horizontal, 6);
                row.append(&widgets::dot(level_color(&line.level)));
                let message = gtk::Label::new(Some(&line.message));
                message.add_css_class("row-name");
                message.set_halign(gtk::Align::Start);
                message.set_hexpand(true);
                message.set_ellipsize(gtk::pango::EllipsizeMode::End);
                row.append(&message);
                let at = gtk::Label::new(Some(short_time(&line.at)));
                at.add_css_class("row-meta");
                at.set_xalign(1.0);
                row.append(&at);
                body.append(&row);
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

fn level_color(level: &str) -> &'static str {
    match level.to_lowercase().as_str() {
        "error" | "fatal" => widgets::RED,
        "warn" | "warning" => widgets::ORANGE,
        _ => widgets::BLUE,
    }
}

use std::cell::RefCell;
use std::rc::Rc;

use deck_core::batbox::BatterySnapshot;
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
    let size = settings.borrow().batbox.size;
    let feed = feed::build(app, "BatBox", size, (150, 230, 330), settings.clone());
    let body = feed.body.clone();
    let feed_size = feed.size;
    let paths_for_tick = paths.clone();
    let settings_for_tick = settings.clone();
    let tick = move || {
        let bat = settings_for_tick.borrow().batbox.clone();
        widgets::clear(&body);
        let Some(snapshot) = snapshot::read_payload::<BatterySnapshot>(&paths_for_tick, "batbox")
        else {
            widgets::add_row(&body, &widgets::status_text(&paths_for_tick, "batbox"));
            return gtk::glib::ControlFlow::Continue;
        };
        if snapshot.batteries.is_empty() {
            widgets::add_row(&body, "No battery");
            let state = match snapshot.ac_online {
                Some(true) => "AC power connected",
                Some(false) => "On battery",
                None => "No power supply found",
            };
            widgets::add_row(&body, state);
            return gtk::glib::ControlFlow::Continue;
        }
        let metrics = gtk::Box::new(
            if feed_size == WidgetSize::Small {
                gtk::Orientation::Vertical
            } else {
                gtk::Orientation::Horizontal
            },
            14,
        );
        metrics.set_halign(gtk::Align::Start);
        for battery in snapshot.batteries.iter().take(2) {
            let color = if battery.percent <= f64::from(bat.low_percent) {
                widgets::RED
            } else if battery.percent <= f64::from(bat.low_percent) + 20.0 {
                widgets::ORANGE
            } else {
                widgets::GREEN
            };
            let label = widgets::metric_label("BATTERY");
            label.set_markup(&widgets::metric_markup(
                "BATTERY",
                &format!("{:.0}%", battery.percent),
                color,
                widgets::WHITE,
            ));
            metrics.append(&label);
            let left = battery
                .minutes_left
                .map(format_minutes)
                .unwrap_or_else(|| "—".into());
            let time = widgets::metric_label("TIME LEFT");
            time.set_markup(&widgets::metric_markup(
                "TIME LEFT",
                &left,
                widgets::CYAN,
                widgets::WHITE,
            ));
            metrics.append(&time);
            let state = gtk::Label::new(None);
            state.add_css_class("metric");
            state.set_markup(&widgets::metric_markup(
                "STATE",
                &battery.status,
                widgets::CYAN,
                widgets::WHITE,
            ));
            metrics.append(&state);
        }
        body.append(&metrics);
        if bat.show_accessories && feed_size != WidgetSize::Small {
            let divider = gtk::Separator::new(gtk::Orientation::Horizontal);
            divider.add_css_class("widget-divider");
            body.append(&divider);
            widgets::section(&body, "ACCESSORIES");
            if snapshot.accessories.is_empty() {
                widgets::add_row(&body, "No accessories");
            } else {
                for accessory in snapshot.accessories.iter().take(5) {
                    let (_, _, value) = widgets::split_row(&body, &accessory.name);
                    value.set_markup(&format!(
                        "<span foreground=\"#8e8e93\">{} {}</span>",
                        accessory
                            .percent
                            .map(|percent| format!("{percent:.0}%"))
                            .unwrap_or_default(),
                        accessory.detail
                    ));
                }
            }
        }
        gtk::glib::ControlFlow::Continue
    };

    tick();
    gtk::glib::timeout_add_seconds_local(30, tick);
    (feed.window, feed.height)
}

fn format_minutes(minutes: u64) -> String {
    if minutes >= 60 {
        format!("{}h {:02}m", minutes / 60, minutes % 60)
    } else {
        format!("{minutes}m")
    }
}

use std::cell::RefCell;
use std::rc::Rc;

use deck_core::clockbox::{self, ClockRow, Zone};
use deck_core::settings::{Settings, WidgetSize};
use gtk4 as gtk;
use gtk4::prelude::*;

use crate::widgets::{self, feed};

pub fn build(
    app: &gtk::Application,
    settings: Rc<RefCell<Settings>>,
) -> (gtk::ApplicationWindow, i32) {
    let size = settings.borrow().clock.size;
    let feed = feed::build(app, "Clock", size, (140, 210, 300), settings.clone());
    let body = feed.body.clone();
    let feed_size = feed.size;
    let settings_for_tick = settings.clone();
    let tick = move || {
        let clock = settings_for_tick.borrow().clock.clone();
        widgets::clear(&body);
        let limit = match feed_size {
            WidgetSize::Small => 1,
            WidgetSize::Medium => 3,
            WidgetSize::Large => 6,
        };
        let now = clockbox::now();
        let ids = if feed_size == WidgetSize::Small {
            clockbox::main_city_id(&clock.city_ids, &clock.main_city_id)
                .into_iter()
                .collect::<Vec<_>>()
        } else {
            clock.city_ids.clone()
        };
        let rows = clockbox::rows(&ids, Zone::Local, now, limit);
        if rows.is_empty() {
            widgets::add_row(&body, "Pick cities in Settings");
            return gtk::glib::ControlFlow::Continue;
        }

        if feed_size == WidgetSize::Small {
            let row = &rows[0];
            let name = gtk::Label::new(Some(&row.name));
            name.add_css_class("clock-name");
            name.set_halign(gtk::Align::Start);
            body.append(&name);
            let time = gtk::Label::new(Some(&row.time));
            time.add_css_class("clock-time-small");
            time.set_halign(gtk::Align::Start);
            body.append(&time);
            if clock.show_relative_day {
                widgets::add_row(&body, &row.day);
            }
            if clock.show_offset {
                widgets::add_row(&body, &row.offset);
            }
            return gtk::glib::ControlFlow::Continue;
        }

        let columns = 3;
        let mut start = 0;
        while start < rows.len() {
            let end = (start + columns).min(rows.len());
            let line = gtk::Box::new(gtk::Orientation::Horizontal, 12);
            line.set_hexpand(true);
            for row in &rows[start..end] {
                line.append(&column(row, &clock));
            }
            for _ in end - start..columns {
                let spacer = gtk::Box::new(gtk::Orientation::Horizontal, 0);
                spacer.set_hexpand(true);
                line.append(&spacer);
            }
            body.append(&line);
            if feed_size == WidgetSize::Large && end < rows.len() {
                let divider = gtk::Separator::new(gtk::Orientation::Horizontal);
                divider.add_css_class("clock-divider");
                body.append(&divider);
            }
            start = end;
        }
        gtk::glib::ControlFlow::Continue
    };

    tick();
    gtk::glib::timeout_add_seconds_local(10, tick);
    (feed.window, feed.height)
}

fn column(row: &ClockRow, clock: &deck_core::settings::ClockBoxSettings) -> gtk::Box {
    let column = gtk::Box::new(gtk::Orientation::Vertical, 2);
    column.set_hexpand(true);
    column.set_halign(gtk::Align::Fill);
    let time = gtk::Label::new(Some(&row.time));
    time.add_css_class("clock-time");
    time.set_halign(gtk::Align::Center);
    let name = gtk::Label::new(Some(&row.name));
    name.add_css_class("clock-name");
    name.set_halign(gtk::Align::Center);
    name.set_ellipsize(gtk::pango::EllipsizeMode::End);
    column.append(&time);
    column.append(&name);
    if clock.show_relative_day {
        let day = gtk::Label::new(Some(&row.day));
        day.add_css_class("row-meta");
        day.set_halign(gtk::Align::Center);
        column.append(&day);
    }
    if clock.show_offset {
        let offset = gtk::Label::new(Some(&row.offset));
        offset.add_css_class("row-meta");
        offset.set_halign(gtk::Align::Center);
        column.append(&offset);
    }
    column
}

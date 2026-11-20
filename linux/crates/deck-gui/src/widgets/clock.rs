use std::cell::RefCell;
use std::rc::Rc;

use deck_core::clockbox::{self, Zone};
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
            widgets::add_row(&body, "Add city IDs in Settings");
            return gtk::glib::ControlFlow::Continue;
        }
        for row in rows {
            if feed_size == WidgetSize::Small {
                let time = gtk::Label::new(Some(&row.time));
                time.add_css_class("title");
                time.set_halign(gtk::Align::Start);
                body.append(&time);
                let mut subtitle = row.name.clone();
                if clock.show_relative_day && row.day != "Today" {
                    subtitle.push_str(&format!("  ·  {}", row.day));
                }
                if clock.show_offset {
                    subtitle.push_str(&format!("  ·  {}", row.offset));
                }
                widgets::add_row(&body, &subtitle);
                continue;
            }
            let mut suffix = Vec::new();
            if clock.show_relative_day && row.day != "Today" {
                suffix.push(row.day.clone());
            }
            if clock.show_offset {
                suffix.push(row.offset.clone());
            }
            let text = if suffix.is_empty() {
                format!("{}   {}", row.name, row.time)
            } else {
                format!("{}   {}   {}", row.name, row.time, suffix.join("  "))
            };
            widgets::add_row(&body, &text);
        }
        gtk::glib::ControlFlow::Continue
    };

    tick();
    gtk::glib::timeout_add_seconds_local(10, tick);
    (feed.window, feed.height)
}

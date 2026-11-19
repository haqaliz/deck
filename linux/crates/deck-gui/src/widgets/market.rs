use std::cell::RefCell;
use std::rc::Rc;

use deck_core::market::MarketSnapshot;
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
    let size = settings.borrow().market.size;
    let feed = feed::build(app, "Market", size, (150, 220, 330));
    let body = feed.body.clone();
    let feed_size = feed.size;
    let paths_for_tick = paths.clone();
    let settings_for_tick = settings.clone();
    let tick = move || {
        let market = settings_for_tick.borrow().market.clone();
        widgets::clear(&body);
        let Some(snapshot) = snapshot::read_payload::<MarketSnapshot>(&paths_for_tick, "marketbox")
        else {
            widgets::add_row(&body, &widgets::status_text(&paths_for_tick, "marketbox"));
            return gtk::glib::ControlFlow::Continue;
        };
        widgets::add_row(&body, snapshot.display_currency.label());

        let limit = match feed_size {
            WidgetSize::Small | WidgetSize::Medium => 4,
            WidgetSize::Large => market.ticker_count.max(1) as usize,
        };
        for row in snapshot.rows.iter().take(limit) {
            let change = if market.show_day_change {
                row.day_change_pct
                    .map(|value| format!("  {value:+.1}%"))
                    .unwrap_or_default()
            } else {
                String::new()
            };
            let label = gtk::Label::new(Some(&format!(
                "{}   {}{change}",
                row.symbol,
                price(row.price)
            )));
            label.add_css_class("metric");
            label.set_halign(gtk::Align::Start);
            label.set_ellipsize(gtk::pango::EllipsizeMode::End);
            if market.show_day_change {
                match row.day_change_pct {
                    Some(value) if value > 0.0 => label.add_css_class("up"),
                    Some(value) if value < 0.0 => label.add_css_class("down"),
                    _ => {}
                }
            }
            body.append(&label);
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

fn price(value: f64) -> String {
    let prefix = "$";
    if value.abs() >= 1_000_000_000.0 {
        format!("{prefix}{:.2}B", value / 1_000_000_000.0)
    } else if value.abs() >= 1_000_000.0 {
        format!("{prefix}{:.2}M", value / 1_000_000.0)
    } else if value.abs() >= 1_000.0 {
        format!("{prefix}{:.0}", value)
    } else if value.abs() >= 1.0 {
        format!("{prefix}{value:.2}")
    } else {
        format!("{prefix}{value:.4}")
    }
}

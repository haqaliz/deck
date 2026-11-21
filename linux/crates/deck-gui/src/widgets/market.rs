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
    let feed = feed::build(app, "Market", size, (150, 220, 330), settings.clone());
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
        let currency = snapshot.display_currency;
        let header = gtk::Label::new(None);
        header.set_markup(&format!(
            "<span foreground=\"{}\">{}</span>",
            widgets::BLUE,
            currency.label()
        ));
        header.set_halign(gtk::Align::Start);
        body.append(&header);

        let limit = match feed_size {
            WidgetSize::Small | WidgetSize::Medium => 4,
            WidgetSize::Large => market.ticker_count.max(1) as usize,
        };
        for row in snapshot.rows.iter().take(limit) {
            let (_, left, right) = widgets::split_row(&body, "");
            left.set_markup(&format!(
                "<span foreground=\"#8e8e93\">{}</span>   <span foreground=\"{}\">{}</span>",
                row.symbol,
                widgets::WHITE,
                price(row.price, currency)
            ));
            if market.show_day_change {
                if let Some(change) = row.day_change_pct {
                    let color = if change >= 0.0 {
                        widgets::GREEN
                    } else {
                        widgets::RED
                    };
                    right.set_markup(&format!(
                        "<span foreground=\"{color}\">{change:+.1}%</span>"
                    ));
                } else {
                    right.set_markup("<span foreground=\"#8e8e93\">–</span>");
                }
            }
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

fn price(value: f64, currency: deck_core::market::MarketCurrency) -> String {
    let prefix = if currency == deck_core::market::MarketCurrency::Usd {
        "$"
    } else {
        ""
    };
    if value.abs() >= 1_000_000_000.0 {
        format!("{prefix}{:.1}B", value / 1_000_000_000.0)
    } else if value.abs() >= 1_000_000.0 {
        format!("{prefix}{:.1}M", value / 1_000_000.0)
    } else if value.abs() >= 1_000.0 {
        format!("{prefix}{}", grouped(value.round() as i64))
    } else if value.abs() >= 1.0 {
        format!("{prefix}{value:.2}")
    } else {
        format!("{prefix}{value:.4}")
    }
}

fn grouped(value: i64) -> String {
    let digits = value.abs().to_string();
    let mut out = String::new();
    for (index, ch) in digits.chars().rev().enumerate() {
        if index > 0 && index % 3 == 0 {
            out.push(',');
        }
        out.push(ch);
    }
    let mut grouped: String = out.chars().rev().collect();
    if value < 0 {
        grouped.insert(0, '-');
    }
    grouped
}

#[cfg(test)]
mod tests {
    use super::{grouped, price};
    use deck_core::market::MarketCurrency;

    #[test]
    fn prices_use_grouping_and_currency_prefix() {
        assert_eq!(grouped(145_807), "145,807");
        assert_eq!(price(145_807.0, MarketCurrency::Irt), "145,807");
        assert_eq!(price(145_807.0, MarketCurrency::Usd), "$145,807");
        assert_eq!(price(497_300_000.0, MarketCurrency::Usd), "$497.3M");
    }
}

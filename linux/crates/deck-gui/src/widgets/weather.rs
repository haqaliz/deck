use std::cell::RefCell;
use std::rc::Rc;

use deck_core::paths::Paths;
use deck_core::settings::{Settings, WidgetSize};
use deck_core::snapshot;
use deck_core::weather::WeatherSnapshot;
use gtk4 as gtk;
use gtk4::prelude::*;

use crate::widgets::{self, feed};

pub fn build(
    app: &gtk::Application,
    settings: Rc<RefCell<Settings>>,
    paths: Paths,
) -> (gtk::ApplicationWindow, i32) {
    let size = settings.borrow().weather.size;
    let feed = feed::build(app, "Weather", size, (150, 220, 290), settings.clone());
    let body = feed.body.clone();
    let feed_size = feed.size;
    let paths_for_tick = paths.clone();
    let settings_for_tick = settings.clone();
    let tick = move || {
        let weather = settings_for_tick.borrow().weather.clone();
        widgets::clear(&body);
        let Some(snapshot) = snapshot::read_payload::<WeatherSnapshot>(&paths_for_tick, "weather")
        else {
            widgets::add_row(&body, &widgets::status_text(&paths_for_tick, "weather"));
            return gtk::glib::ControlFlow::Continue;
        };

        let (temp, unit) = if weather.units_fahrenheit {
            (snapshot.condition.temp_f, "°F")
        } else {
            (snapshot.condition.temp_c, "°C")
        };
        let temp = temp
            .map(|value| format!("{value:.0}{unit}"))
            .unwrap_or_else(|| "—".into());

        let headline = gtk::Box::new(gtk::Orientation::Horizontal, 8);
        let glyph = gtk::Label::new(Some(deck_core::weather::glyph(snapshot.condition.code)));
        glyph.add_css_class("weather-glyph");
        let temperature = gtk::Label::new(Some(&temp));
        temperature.add_css_class("weather-temp");
        headline.append(&glyph);
        headline.append(&temperature);

        let location = gtk::Label::new(Some(&if snapshot.country.is_empty() {
            snapshot.location.clone()
        } else {
            format!("{}, {}", snapshot.location, snapshot.country)
        }));
        location.add_css_class("weather-location");
        location.set_hexpand(true);
        location.set_xalign(1.0);
        location.set_ellipsize(gtk::pango::EllipsizeMode::End);
        headline.append(&location);
        body.append(&headline);

        let feels = if weather.units_fahrenheit {
            snapshot.condition.feels_like_f
        } else {
            snapshot.condition.feels_like_c
        };
        let mut details = Vec::new();
        if let Some(feels) = feels {
            details.push(format!("FEELS {feels:.0}{unit}"));
        }
        if let Some(humidity) = snapshot.condition.humidity {
            details.push(format!("HUMIDITY {humidity:.0}%"));
        }
        if let Some(wind) = snapshot.condition.wind_kmph {
            details.push(format!("{} {wind:.0} km/h", snapshot.condition.wind_dir));
        }
        let detail = gtk::Label::new(Some(&details.join("   ")));
        detail.add_css_class("row-meta");
        detail.set_halign(gtk::Align::Start);
        body.append(&detail);

        if weather.show_forecast && feed_size != WidgetSize::Small {
            widgets::section(&body, "FORECAST");
            let line = gtk::Box::new(gtk::Orientation::Horizontal, 10);
            line.set_hexpand(true);
            for day in snapshot.days.iter().take(3) {
                let high = if weather.units_fahrenheit {
                    day.max_temp_f
                } else {
                    day.max_temp_c
                };
                let low = if weather.units_fahrenheit {
                    day.min_temp_f
                } else {
                    day.min_temp_c
                };
                let temps = match (high, low) {
                    (Some(high), Some(low)) => format!("{high:.0}°  {low:.0}°"),
                    _ => "—".into(),
                };
                let column = gtk::Box::new(gtk::Orientation::Vertical, 2);
                column.set_hexpand(true);
                let date = gtk::Label::new(Some(day.date.get(5..).unwrap_or(&day.date)));
                date.add_css_class("row-meta");
                date.set_halign(gtk::Align::Center);
                let icon = gtk::Label::new(Some(deck_core::weather::glyph(day.code)));
                icon.add_css_class("weather-glyph-small");
                icon.set_halign(gtk::Align::Center);
                let temps = gtk::Label::new(Some(&temps));
                temps.add_css_class("weather-temps");
                temps.set_halign(gtk::Align::Center);
                column.append(&date);
                column.append(&icon);
                column.append(&temps);
                line.append(&column);
            }
            for _ in snapshot.days.len().min(3)..3 {
                let spacer = gtk::Box::new(gtk::Orientation::Horizontal, 0);
                spacer.set_hexpand(true);
                line.append(&spacer);
            }
            body.append(&line);
        }
        gtk::glib::ControlFlow::Continue
    };

    tick();
    gtk::glib::timeout_add_seconds_local(5, tick);
    (feed.window, feed.height)
}

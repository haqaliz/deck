use std::cell::RefCell;
use std::rc::Rc;

use deck_core::paths::Paths;
use deck_core::settings::Settings;
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

        let location = if snapshot.country.is_empty() {
            snapshot.location.clone()
        } else {
            format!("{}, {}", snapshot.location, snapshot.country)
        };
        widgets::add_row(&body, &location);

        let (temp, unit) = if weather.units_fahrenheit {
            (snapshot.condition.temp_f, "°F")
        } else {
            (snapshot.condition.temp_c, "°C")
        };
        let temp = temp
            .map(|value| format!("{value:.0}{unit}"))
            .unwrap_or_else(|| "—".into());
        let headline = gtk::Label::new(Some(&format!(
            "{}  {temp}",
            deck_core::weather::glyph(snapshot.condition.code)
        )));
        headline.add_css_class("title");
        headline.set_halign(gtk::Align::Start);
        body.append(&headline);
        widgets::add_row(&body, &snapshot.condition.desc);

        let feels = if weather.units_fahrenheit {
            snapshot.condition.feels_like_f
        } else {
            snapshot.condition.feels_like_c
        };
        let mut details = Vec::new();
        if let Some(feels) = feels {
            details.push(format!("Feels {feels:.0}{unit}"));
        }
        if let Some(humidity) = snapshot.condition.humidity {
            details.push(format!("Humidity {humidity:.0}%"));
        }
        if let Some(wind) = snapshot.condition.wind_kmph {
            details.push(format!("{} {wind:.0} km/h", snapshot.condition.wind_dir));
        }
        if !details.is_empty() {
            widgets::add_row(&body, &details.join("   "));
        }

        if weather.show_forecast && feed_size != deck_core::settings::WidgetSize::Small {
            widgets::section(&body, "FORECAST");
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
                let date = day.date.get(5..).unwrap_or(&day.date);
                let temps = match (high, low) {
                    (Some(high), Some(low)) => format!("{high:.0}/{low:.0}"),
                    _ => "—".into(),
                };
                widgets::add_row(
                    &body,
                    &format!(
                        "{date}  {}  {temps}  {}",
                        deck_core::weather::glyph(day.code),
                        day.desc
                    ),
                );
            }
        }
        gtk::glib::ControlFlow::Continue
    };

    tick();
    gtk::glib::timeout_add_seconds_local(5, tick);
    (feed.window, feed.height)
}

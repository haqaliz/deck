use std::cell::RefCell;
use std::rc::Rc;

use deck_core::gitbox::GitBoxSnapshot;
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
    let size = settings.borrow().git.size;
    let feed = feed::build(app, "Git", size, (140, 220, 330), settings.clone());
    let body = feed.body.clone();
    let feed_size = feed.size;
    let paths_for_tick = paths.clone();
    let settings_for_tick = settings.clone();
    let tick = move || {
        let git = settings_for_tick.borrow().git.clone();
        widgets::clear(&body);
        let Some(snapshot) = snapshot::read_payload::<GitBoxSnapshot>(&paths_for_tick, "gitbox")
        else {
            widgets::add_row(&body, &widgets::status_text(&paths_for_tick, "gitbox"));
            return gtk::glib::ControlFlow::Continue;
        };

        let summary = gtk::Box::new(gtk::Orientation::Horizontal, 14);
        let today = widgets::metric_label("TODAY");
        today.set_markup(&widgets::metric_markup(
            "TODAY",
            &snapshot.today_count.to_string(),
            widgets::ORANGE,
            widgets::WHITE,
        ));
        let streak = widgets::metric_label("STREAK");
        streak.set_markup(&widgets::metric_markup(
            "STREAK",
            &format!("{}d", snapshot.streak),
            widgets::CYAN,
            widgets::WHITE,
        ));
        summary.append(&today);
        summary.append(&streak);
        body.append(&summary);

        if git.show_chart && feed_size != WidgetSize::Small {
            let chart = gtk::DrawingArea::new();
            chart.set_size_request(-1, 70);
            let values: Vec<i64> = snapshot.days.iter().map(|day| day.count as i64).collect();
            chart.set_draw_func(move |_, cr, width, height| {
                widgets::draw_bars(cr, width, height, &values, true);
            });
            body.append(&chart);
        }

        if git.show_repos && feed_size == WidgetSize::Large {
            widgets::section(&body, "REPOS");
            for repo in snapshot.repos.iter().take(git.repo_count.max(1) as usize) {
                let (_, _, count) = widgets::split_row(&body, &repo.short_name);
                count.set_markup(&format!(
                    "<span foreground=\"{}\">{}</span>",
                    widgets::ORANGE,
                    repo.today_count
                ));
            }
            if snapshot.repos.is_empty() {
                widgets::add_row(&body, "No commits in the last 15 days");
            }
        }
        gtk::glib::ControlFlow::Continue
    };

    tick();
    gtk::glib::timeout_add_seconds_local(5, tick);
    (feed.window, feed.height)
}

use std::cell::RefCell;
use std::rc::Rc;

use deck_core::paths::Paths;
use deck_core::settings::{Settings, WidgetSize};
use deck_core::ship::{self, ShipBoxSnapshot, ShipStatus};
use deck_core::snapshot;
use gtk4 as gtk;

use crate::widgets::{self, feed};

pub fn build(
    app: &gtk::Application,
    settings: Rc<RefCell<Settings>>,
    paths: Paths,
) -> (gtk::ApplicationWindow, i32) {
    let size = settings.borrow().ship.size;
    let feed = feed::build(app, "Ship", size, (140, 220, 330), settings.clone());
    let body = feed.body.clone();
    let feed_size = feed.size;
    let paths_for_tick = paths.clone();
    let settings_for_tick = settings.clone();
    let tick = move || {
        let ship = settings_for_tick.borrow().ship.clone();
        widgets::clear(&body);
        let Some(snapshot) = snapshot::read_payload::<ShipBoxSnapshot>(&paths_for_tick, "shipbox")
        else {
            widgets::add_row(&body, &widgets::status_text(&paths_for_tick, "shipbox"));
            return gtk::glib::ControlFlow::Continue;
        };
        let totals = ship::totals_line(&snapshot.runs);
        widgets::add_row(
            &body,
            if totals.is_empty() {
                "No runs yet"
            } else {
                &totals
            },
        );

        if ship.show_list && feed_size != WidgetSize::Small {
            widgets::section(&body, "RUNS");
            for run in snapshot.runs.iter().take(ship.run_count.max(1) as usize) {
                let repo = run.repo.rsplit('/').next().unwrap_or(&run.repo);
                let detail = if run.branch.is_empty() {
                    run.status.label().to_string()
                } else {
                    format!("{} · {}", run.branch, run.status.label())
                };
                let text = format!(
                    "{} {} #{}   {detail}",
                    glyph(run.status),
                    repo,
                    run.run_number
                );
                if run.html_url.is_empty() {
                    widgets::add_row(&body, &text);
                } else {
                    widgets::link_row(&body, &text, &run.html_url);
                }
            }
            if snapshot.runs.is_empty() {
                widgets::add_row(&body, "No workflow runs returned");
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

fn glyph(status: ShipStatus) -> &'static str {
    match status {
        ShipStatus::Success => "✓",
        ShipStatus::Failure => "✗",
        ShipStatus::Running => "●",
        ShipStatus::Queued => "…",
        ShipStatus::Neutral => "·",
    }
}

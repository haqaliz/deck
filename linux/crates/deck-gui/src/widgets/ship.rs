use std::cell::RefCell;
use std::rc::Rc;

use deck_core::paths::Paths;
use deck_core::settings::{Settings, WidgetSize};
use deck_core::ship::{ShipBoxSnapshot, ShipStatus};
use deck_core::snapshot;
use gtk4 as gtk;
use gtk4::prelude::*;

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

        let repo = snapshot
            .repos
            .first()
            .cloned()
            .or_else(|| snapshot.runs.first().map(|run| run.repo.clone()))
            .unwrap_or_default();
        let passed = snapshot
            .runs
            .iter()
            .filter(|run| run.status == ShipStatus::Success)
            .count();
        let (_, left, right) = widgets::split_row(&body, &repo);
        left.add_css_class("row-title");
        right.set_markup(&format!(
            "<span foreground=\"{}\">{passed} pass</span>",
            widgets::WHITE
        ));

        if !snapshot.runs.is_empty() {
            let counts = gtk::Box::new(gtk::Orientation::Horizontal, 10);
            for (status, title, color) in [
                (ShipStatus::Success, "PASS", widgets::GREEN),
                (ShipStatus::Failure, "FAIL", widgets::RED),
                (ShipStatus::Running, "RUN", widgets::BLUE),
                (ShipStatus::Queued, "QUEUED", widgets::ORANGE),
            ] {
                let count = snapshot
                    .runs
                    .iter()
                    .filter(|run| run.status == status)
                    .count();
                let label = gtk::Label::new(None);
                label.set_markup(&widgets::metric_markup(
                    title,
                    &count.to_string(),
                    color,
                    widgets::WHITE,
                ));
                counts.append(&label);
            }
            body.append(&counts);
        }

        if ship.show_list && feed_size != WidgetSize::Small {
            widgets::section(&body, "RUNS");
            for run in snapshot.runs.iter().take(ship.run_count.max(1) as usize) {
                let repo = run.repo.rsplit('/').next().unwrap_or(&run.repo);
                let line = gtk::Box::new(gtk::Orientation::Horizontal, 6);
                line.append(&widgets::dot(status_color(run.status)));
                let title = format!("{repo} #{}", run.run_number);
                if run.html_url.is_empty() {
                    let label = gtk::Label::new(Some(&title));
                    label.add_css_class("row-name");
                    label.set_halign(gtk::Align::Start);
                    line.append(&label);
                } else {
                    let link = gtk::LinkButton::with_label(&run.html_url, &title);
                    link.add_css_class("link-row");
                    link.set_halign(gtk::Align::Start);
                    line.append(&link);
                }
                let detail = gtk::Label::new(None);
                detail.add_css_class("row-meta");
                detail.set_hexpand(true);
                detail.set_xalign(1.0);
                detail.set_ellipsize(gtk::pango::EllipsizeMode::End);
                detail.set_markup(&format!(
                    "<span foreground=\"#8e8e93\">{}</span>",
                    if run.branch.is_empty() {
                        run.status.label().to_string()
                    } else {
                        format!("{} · {}", run.branch, run.status.label())
                    }
                ));
                line.append(&detail);
                body.append(&line);
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

fn status_color(status: ShipStatus) -> &'static str {
    match status {
        ShipStatus::Success => widgets::GREEN,
        ShipStatus::Failure => widgets::RED,
        ShipStatus::Running => widgets::BLUE,
        ShipStatus::Queued => widgets::ORANGE,
        ShipStatus::Neutral => "#8e8e93",
    }
}

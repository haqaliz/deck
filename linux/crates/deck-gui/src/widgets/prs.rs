use std::cell::RefCell;
use std::rc::Rc;

use deck_core::paths::Paths;
use deck_core::prs::{PrBoxSnapshot, PrProvider};
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
    let size = settings.borrow().prs.size;
    let feed = feed::build(
        app,
        "Pull requests",
        size,
        (140, 240, 340),
        settings.clone(),
    );
    let body = feed.body.clone();
    let feed_size = feed.size;
    let paths_for_tick = paths.clone();
    let settings_for_tick = settings.clone();
    let tick = move || {
        let pr_settings = settings_for_tick.borrow().prs.clone();
        widgets::clear(&body);
        let Some(snapshot) = snapshot::read_payload::<PrBoxSnapshot>(&paths_for_tick, "prbox")
        else {
            widgets::add_row(&body, &widgets::status_text(&paths_for_tick, "prbox"));
            return gtk::glib::ControlFlow::Continue;
        };
        let summary = gtk::Box::new(gtk::Orientation::Horizontal, 14);
        for (title, count, color) in [
            ("MINE", snapshot.authored_count, widgets::GREEN),
            ("REVIEW", snapshot.reviewing_count, widgets::ORANGE),
        ] {
            let label = widgets::metric_label(title);
            label.set_markup(&widgets::metric_markup(
                title,
                &count.to_string(),
                color,
                widgets::WHITE,
            ));
            summary.append(&label);
        }
        body.append(&summary);

        if pr_settings.show_list && feed_size != WidgetSize::Small {
            for row in snapshot
                .pull_requests
                .iter()
                .take(pr_settings.pr_count.max(1) as usize)
            {
                let provider = match row.provider {
                    PrProvider::Github => "GitHub",
                    PrProvider::AzureDevOps => "Azure",
                };
                let color = if row.role == deck_core::prs::PrRole::Authored {
                    widgets::GREEN
                } else {
                    widgets::ORANGE
                };
                let line = gtk::Box::new(gtk::Orientation::Horizontal, 6);
                line.append(&widgets::dot(color));
                let title = format!("{} #{}  {}", row.repo, row.number, row.title);
                if row.url.is_empty() {
                    let label = gtk::Label::new(Some(&title));
                    label.add_css_class("row-name");
                    label.set_halign(gtk::Align::Start);
                    label.set_ellipsize(gtk::pango::EllipsizeMode::End);
                    line.append(&label);
                } else {
                    let link = gtk::LinkButton::with_label(&row.url, &title);
                    link.add_css_class("link-row");
                    link.set_halign(gtk::Align::Start);
                    line.append(&link);
                }
                body.append(&line);
                widgets::add_row(
                    &body,
                    &format!(
                        "{provider} · {} {}",
                        if row.role == deck_core::prs::PrRole::Authored {
                            "authored"
                        } else {
                            "review"
                        },
                        if row.is_draft { "· draft" } else { "" }
                    ),
                );
            }
            if snapshot.pull_requests.is_empty() {
                widgets::add_row(&body, "No open PRs");
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

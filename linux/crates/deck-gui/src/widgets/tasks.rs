use std::cell::RefCell;
use std::rc::Rc;

use deck_core::paths::Paths;
use deck_core::settings::{Settings, WidgetSize};
use deck_core::snapshot;
use deck_core::tasks::{self, TaskBoxSnapshot, TaskLane};
use gtk4 as gtk;
use gtk4::prelude::*;

use crate::widgets::{self, feed};

pub fn build(
    app: &gtk::Application,
    settings: Rc<RefCell<Settings>>,
    paths: Paths,
) -> (gtk::ApplicationWindow, i32) {
    let size = settings.borrow().tasks.size;
    let feed = feed::build(app, "Tasks", size, (140, 240, 340), settings.clone());
    let body = feed.body.clone();
    let feed_size = feed.size;
    let paths_for_tick = paths.clone();
    let settings_for_tick = settings.clone();
    let tick = move || {
        let task_settings = settings_for_tick.borrow().tasks.clone();
        widgets::clear(&body);
        let Some(snapshot) = snapshot::read_payload::<TaskBoxSnapshot>(&paths_for_tick, "taskbox")
        else {
            widgets::add_row(&body, &widgets::status_text(&paths_for_tick, "taskbox"));
            return gtk::glib::ControlFlow::Continue;
        };
        let total = format!(
            "{}{} {}",
            snapshot.total_count,
            if snapshot.total_is_lower_bound {
                "+"
            } else {
                ""
            },
            if snapshot.is_custom_query {
                "items"
            } else {
                "open"
            }
        );
        let (_, total_label, sprint_label) = widgets::split_row(&body, &total);
        total_label.add_css_class("row-title");
        if let Some(sprint) = &snapshot.sprint {
            sprint_label.set_markup(&format!("<span foreground=\"#8e8e93\">{sprint}</span>"));
        }

        if task_settings.show_legend && feed_size != WidgetSize::Small {
            let legend = gtk::Box::new(gtk::Orientation::Horizontal, 10);
            for (lane, count) in tasks::lane_counts(&snapshot.tasks) {
                let always = matches!(
                    lane,
                    TaskLane::Todo | TaskLane::InProgress | TaskLane::Testing
                );
                if !always && count == 0 {
                    continue;
                }
                let label = gtk::Label::new(None);
                label.set_markup(&widgets::metric_markup(
                    lane.label(),
                    &count.to_string(),
                    lane_color(lane),
                    widgets::WHITE,
                ));
                legend.append(&label);
            }
            body.append(&legend);
        }

        if task_settings.show_list && feed_size != WidgetSize::Small {
            for task in snapshot
                .tasks
                .iter()
                .take(task_settings.task_count.max(1) as usize)
            {
                let line = gtk::Box::new(gtk::Orientation::Horizontal, 6);
                line.append(&widgets::dot(lane_color(tasks::lane(&task.state))));
                let text = format!("#{}  {}", task.id, task.title);
                if task.url.is_empty() {
                    let label = gtk::Label::new(Some(&text));
                    label.add_css_class("row-name");
                    label.set_halign(gtk::Align::Start);
                    label.set_ellipsize(gtk::pango::EllipsizeMode::End);
                    line.append(&label);
                } else {
                    widgets::link_row(&line, &text, &task.url);
                }
                body.append(&line);
            }
            if snapshot.tasks.is_empty() {
                widgets::add_row(&body, "Nothing assigned");
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

fn lane_color(lane: TaskLane) -> &'static str {
    match lane {
        TaskLane::Todo => widgets::BLUE,
        TaskLane::InProgress => widgets::ORANGE,
        TaskLane::Testing => widgets::PINK,
        TaskLane::Done => widgets::GREEN,
        TaskLane::Other => "#8e8e93",
    }
}

use std::cell::RefCell;
use std::rc::Rc;

use deck_core::paths::Paths;
use deck_core::settings::{Settings, WidgetSize};
use deck_core::snapshot;
use deck_core::tasks::{self, TaskBoxSnapshot};
use gtk4 as gtk;

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
        widgets::add_row(&body, &total);

        if task_settings.show_legend && feed_size != WidgetSize::Small {
            let legend = tasks::lane_counts(&snapshot.tasks)
                .iter()
                .filter(|(_, count)| *count > 0)
                .map(|(lane, count)| format!("{} {count}", lane.label()))
                .collect::<Vec<_>>()
                .join(" · ");
            if !legend.is_empty() {
                widgets::add_row(&body, &legend);
            }
        }

        if task_settings.show_list && feed_size != WidgetSize::Small {
            for task in snapshot
                .tasks
                .iter()
                .take(task_settings.task_count.max(1) as usize)
            {
                let title = format!("#{}  {}", task.id, task.title);
                if task.url.is_empty() {
                    widgets::add_row(&body, &title);
                } else {
                    widgets::link_row(&body, &title, &task.url);
                }
                widgets::add_row(&body, &format!("{} · {}", task.item_type, task.state));
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

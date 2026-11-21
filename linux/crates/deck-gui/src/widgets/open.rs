use std::cell::RefCell;
use std::rc::Rc;

use deck_core::openbox::OpenCodeSnapshot;
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
    let size = settings.borrow().openbox.size;
    let feed = feed::build(app, "Open", size, (150, 230, 340), settings.clone());
    let body = feed.body.clone();
    let feed_size = feed.size;
    let paths_for_tick = paths.clone();
    let settings_for_tick = settings.clone();
    let tick = move || {
        let openbox = settings_for_tick.borrow().openbox.clone();
        widgets::clear(&body);
        let Some(snapshot) =
            snapshot::read_payload::<OpenCodeSnapshot>(&paths_for_tick, "opencode")
        else {
            widgets::add_row(&body, &widgets::status_text(&paths_for_tick, "opencode"));
            return gtk::glib::ControlFlow::Continue;
        };

        let summary = gtk::Box::new(gtk::Orientation::Horizontal, 12);
        for (title, value, color) in [
            ("TODAY", snapshot.sessions.to_string(), widgets::BLUE),
            ("IN", widgets::format_tokens(snapshot.input), widgets::CYAN),
            (
                "OUT",
                widgets::format_tokens(snapshot.output),
                widgets::GREEN,
            ),
            (
                "COST",
                widgets::format_money(snapshot.cost),
                widgets::ORANGE,
            ),
        ] {
            let label = widgets::metric_label(title);
            label.set_markup(&widgets::metric_markup(
                title,
                &value,
                color,
                widgets::WHITE,
            ));
            summary.append(&label);
        }
        body.append(&summary);

        if openbox.show_models && feed_size != WidgetSize::Small {
            widgets::section(&body, "MODELS");
            for model in snapshot
                .models
                .iter()
                .take(openbox.model_count.max(1) as usize)
            {
                let (_, _, value) = widgets::split_row(&body, &model.model);
                value.set_markup(&format!(
                    "<span foreground=\"#8e8e93\">{} · {}/{}</span>",
                    widgets::format_money(model.cost),
                    widgets::format_tokens(model.input),
                    widgets::format_tokens(model.output)
                ));
            }
            if snapshot.models.is_empty() {
                widgets::add_row(&body, "No model usage yet");
            }
        }

        if openbox.show_tools && feed_size != WidgetSize::Small {
            widgets::section(&body, "TOOLS");
            for tool in snapshot
                .tools
                .iter()
                .take(openbox.tool_count.max(1) as usize)
            {
                let (_, _, count) = widgets::split_row(&body, &tool.tool);
                count.set_markup(&format!(
                    "<span foreground=\"#8e8e93\">{}</span>",
                    tool.count
                ));
            }
            if snapshot.tools.is_empty() {
                widgets::add_row(&body, "No tool calls yet");
            }
        }

        if openbox.show_sessions && feed_size == WidgetSize::Large {
            widgets::section(&body, "SESSIONS");
            for session in snapshot
                .session_list
                .iter()
                .take(openbox.session_count.max(1) as usize)
            {
                let (_, _, tokens) = widgets::split_row(&body, &session.title);
                tokens.set_markup(&format!(
                    "<span foreground=\"#8e8e93\">{}/{}</span>",
                    widgets::format_tokens(session.input),
                    widgets::format_tokens(session.output)
                ));
            }
            if snapshot.session_list.is_empty() {
                widgets::add_row(&body, "No sessions in the last 14 days");
            }
        }
        gtk::glib::ControlFlow::Continue
    };

    tick();
    gtk::glib::timeout_add_seconds_local(5, tick);
    (feed.window, feed.height)
}

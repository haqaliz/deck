use std::cell::RefCell;
use std::rc::Rc;
use std::sync::mpsc;
use std::time::Duration;

use chrono::{DateTime, Utc};
use deck_core::clipbox::{self, ClipItem};
use deck_core::paths::Paths;
use deck_core::settings::{Settings, WidgetSize};
use gtk4 as gtk;
use gtk4::prelude::*;

use crate::widgets::{self, feed};

pub fn build(
    app: &gtk::Application,
    settings: Rc<RefCell<Settings>>,
    paths: Paths,
) -> (gtk::ApplicationWindow, i32) {
    let size = settings.borrow().clipbox.size;
    let feed = feed::build(app, "ClipBox", size, (150, 230, 330), settings.clone());
    let body = feed.body.clone();
    let feed_size = feed.size;
    let history = Rc::new(RefCell::new(clipbox::load(&paths).unwrap_or_default()));
    let last_error = Rc::new(RefCell::new(None::<String>));

    let settings_for_render = settings.clone();
    let body_for_render = body.clone();
    let history_for_render = history.clone();
    let error_for_render = last_error.clone();
    let render = Rc::new(move || {
        let settings = settings_for_render.borrow().clipbox.clone();
        widgets::clear(&body_for_render);
        let items = history_for_render.borrow();
        if items.items.is_empty() {
            if let Some(error) = error_for_render.borrow().as_ref() {
                widgets::add_row(&body_for_render, error);
            } else {
                widgets::add_row(&body_for_render, "No copies yet");
            }
            return;
        }
        let count = gtk::Label::new(Some(&items.items.len().to_string()));
        count.add_css_class("row-meta");
        count.set_halign(gtk::Align::End);
        body_for_render.append(&count);
        if !settings.show_list {
            return;
        }
        let limit = match feed_size {
            WidgetSize::Small => 2,
            WidgetSize::Medium => 3,
            WidgetSize::Large => settings.history_count.max(1) as usize,
        };
        for item in items.items.iter().take(limit) {
            add_row(&body_for_render, item, &settings);
        }
    });
    render();

    let (tx, rx) = mpsc::channel::<Result<String, String>>();
    std::thread::spawn(move || {
        let mut last = String::new();
        loop {
            match clipbox::read_text() {
                Ok(text) => {
                    if !text.trim().is_empty() && text != last {
                        last = text.clone();
                        let _ = tx.send(Ok(text));
                    }
                }
                Err(error) => {
                    let _ = tx.send(Err(error));
                }
            }
            std::thread::sleep(Duration::from_secs(1));
        }
    });

    let render_for_poll = render.clone();
    let history_for_poll = history.clone();
    let error_for_poll = last_error.clone();
    let paths_for_poll = paths.clone();
    gtk::glib::timeout_add_local(Duration::from_secs(1), move || {
        while let Ok(message) = rx.try_recv() {
            match message {
                Ok(text) => {
                    *error_for_poll.borrow_mut() = None;
                    let at = Utc::now().to_rfc3339();
                    let mut snapshot = history_for_poll.borrow_mut();
                    if clipbox::push(&mut snapshot, &text, &at, 50) {
                        let _ = clipbox::save(&paths_for_poll, &snapshot);
                        drop(snapshot);
                        render_for_poll();
                    }
                }
                Err(error) => *error_for_poll.borrow_mut() = Some(error),
            }
        }
        gtk::glib::ControlFlow::Continue
    });

    (feed.window, feed.height)
}

fn add_row(body: &gtk::Box, item: &ClipItem, settings: &deck_core::settings::ClipBoxSettings) {
    let button = gtk::Button::new();
    button.add_css_class("link-row");
    button.set_halign(gtk::Align::Fill);
    let line = gtk::Box::new(gtk::Orientation::Horizontal, 6);
    let color = match item.kind.as_str() {
        "file" => settings.file_color.as_str(),
        _ => settings.text_color.as_str(),
    };
    line.append(&widgets::dot(color));
    let column = gtk::Box::new(gtk::Orientation::Vertical, 0);
    column.set_hexpand(true);
    let preview = gtk::Label::new(Some(&item.preview));
    preview.add_css_class("row-name");
    preview.set_halign(gtk::Align::Start);
    preview.set_ellipsize(gtk::pango::EllipsizeMode::End);
    let when = gtk::Label::new(Some(&relative_time(&item.at)));
    when.add_css_class("row-meta");
    when.set_halign(gtk::Align::Start);
    column.append(&preview);
    column.append(&when);
    line.append(&column);
    button.set_child(Some(&line));
    let content = item.content.clone();
    button.connect_clicked(move |_| {
        let content = content.clone();
        std::thread::spawn(move || {
            let _ = clipbox::write_text(&content);
        });
    });
    body.append(&button);
}

fn relative_time(value: &str) -> String {
    let Ok(at) = DateTime::parse_from_rfc3339(value) else {
        return String::new();
    };
    let seconds = Utc::now()
        .signed_duration_since(at.with_timezone(&Utc))
        .num_seconds()
        .max(0);
    match seconds {
        0..=59 => "now".into(),
        60..=3599 => format!("{}m ago", seconds / 60),
        3600..=86399 => format!("{}h ago", seconds / 3600),
        _ => format!("{}d ago", seconds / 86400),
    }
}

use std::cell::RefCell;
use std::rc::Rc;

use deck_core::settings::{Settings, WidgetSize};
use gtk4 as gtk;
use gtk4::prelude::*;

use crate::widgets;

/// Shared layout for the API/feed widgets: header, scrolling body, fixed size.
pub struct Feed {
    pub window: gtk::ApplicationWindow,
    pub body: gtk::Box,
    pub height: i32,
    pub size: WidgetSize,
}

pub fn build(
    app: &gtk::Application,
    title: &str,
    size: WidgetSize,
    heights: (i32, i32, i32),
    settings: Rc<RefCell<Settings>>,
) -> Feed {
    let height = widgets::height(size, heights.0, heights.1, heights.2);
    let spec = deck_platform::surface::WidgetSpec {
        width: 320,
        height,
        top: 48,
        left: 24,
        title: title.into(),
    };
    let window = deck_platform::surface::widget_window(app, &spec);
    window.add_css_class("deck-surface");

    let content = gtk::Box::new(gtk::Orientation::Vertical, 4);
    content.set_margin_top(12);
    content.set_margin_bottom(12);
    content.set_margin_start(14);
    content.set_margin_end(14);

    let header = gtk::Label::new(Some(&title.to_uppercase()));
    header.add_css_class("subtitle");
    header.set_halign(gtk::Align::Start);
    header.set_hexpand(true);
    header.set_tooltip_text(Some("Drag to move"));
    content.append(&crate::ui::movable_header(&window, &header, settings));

    let scroll = gtk::ScrolledWindow::new();
    scroll.set_policy(gtk::PolicyType::Never, gtk::PolicyType::Automatic);
    scroll.set_vexpand(true);
    let body = gtk::Box::new(gtk::Orientation::Vertical, 3);
    scroll.set_child(Some(&body));
    content.append(&scroll);
    window.set_child(Some(&content));

    Feed {
        window,
        body,
        height,
        size,
    }
}

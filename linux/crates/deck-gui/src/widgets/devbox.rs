use std::cell::RefCell;
use std::rc::Rc;

use deck_core::devbox::{docker_containers, listening_ports};
use deck_core::settings::{Settings, WidgetSize};
use gtk4 as gtk;
use gtk4::prelude::*;

use crate::widgets;

pub fn build(
    app: &gtk::Application,
    settings: Rc<RefCell<Settings>>,
) -> (gtk::ApplicationWindow, i32) {
    let (size, refresh_seconds) = {
        let devbox = &settings.borrow().devbox;
        (devbox.size, devbox.refresh_seconds)
    };
    let height = widgets::height(size, 120, 230, 300);
    let spec = deck_platform::surface::WidgetSpec {
        width: 320,
        height,
        top: 420,
        left: 460,
        title: "DevBox".into(),
    };
    let window = deck_platform::surface::widget_window(app, &spec);
    window.add_css_class("deck-surface");

    let content = gtk::Box::new(gtk::Orientation::Vertical, 4);
    content.set_margin_top(12);
    content.set_margin_bottom(12);
    content.set_margin_start(14);
    content.set_margin_end(14);

    let header = gtk::Label::new(Some("DEVBOX"));
    header.add_css_class("subtitle");
    header.set_halign(gtk::Align::Start);
    content.append(&header);

    let summary = gtk::Box::new(gtk::Orientation::Horizontal, 18);
    summary.set_halign(gtk::Align::Start);
    let ports_count = widgets::metric_label("PORTS");
    let containers_count = widgets::metric_label("CONTAINERS");
    summary.append(&ports_count);
    summary.append(&containers_count);
    content.append(&summary);

    let ports_section = (size != WidgetSize::Small).then(|| {
        let header = gtk::Label::new(Some("PORTS"));
        header.add_css_class("section");
        header.set_halign(gtk::Align::Start);
        let rows = gtk::Box::new(gtk::Orientation::Vertical, 1);
        content.append(&header);
        content.append(&rows);
        (header, rows)
    });

    let containers_section = (size == WidgetSize::Large).then(|| {
        let header = gtk::Label::new(Some("CONTAINERS"));
        header.add_css_class("section");
        header.set_halign(gtk::Align::Start);
        let rows = gtk::Box::new(gtk::Orientation::Vertical, 1);
        content.append(&header);
        content.append(&rows);
        (header, rows)
    });

    window.set_child(Some(&content));

    let interval = refresh_seconds.clamp(1, 3600) as u32;
    let settings_for_tick = settings.clone();
    let ports_count_for_tick = ports_count.clone();
    let containers_count_for_tick = containers_count.clone();
    let ports_for_tick = ports_section.clone();
    let containers_for_tick = containers_section.clone();
    let tick = move || {
        let devbox = settings_for_tick.borrow().devbox.clone();

        let listeners = listening_ports().unwrap_or_default();
        let containers = docker_containers();

        ports_count_for_tick.set_text(&format!("PORTS  {}", listeners.len()));
        containers_count_for_tick.set_text(&format!("CONTAINERS  {}", containers.len()));

        if let Some((header, rows)) = &ports_for_tick {
            header.set_visible(devbox.show_ports);
            rows.set_visible(devbox.show_ports);
            widgets::clear(rows);
            if devbox.show_ports {
                if listeners.is_empty() {
                    widgets::add_row(rows, "none");
                } else {
                    for listener in listeners.iter().take(devbox.port_count.max(1) as usize) {
                        widgets::add_row(
                            rows,
                            &format!("{}  :{}", listener.protocol, listener.port),
                        );
                    }
                }
            }
        }

        if let Some((header, rows)) = &containers_for_tick {
            header.set_visible(devbox.show_containers);
            rows.set_visible(devbox.show_containers);
            widgets::clear(rows);
            if devbox.show_containers {
                if containers.is_empty() {
                    widgets::add_row(rows, "none");
                } else {
                    for container in containers
                        .iter()
                        .take(devbox.container_count.max(1) as usize)
                    {
                        widgets::add_row(
                            rows,
                            &format!("{}  {}", container.name, container.status),
                        );
                    }
                }
            }
        }
        gtk::glib::ControlFlow::Continue
    };

    tick();
    gtk::glib::timeout_add_seconds_local(interval, tick);
    (window, height)
}

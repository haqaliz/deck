use std::cell::RefCell;
use std::path::PathBuf;
use std::rc::Rc;

use deck_core::paths::Paths;
use deck_core::settings::{Settings, WidgetSize};
use gtk4 as gtk;
use gtk4::prelude::*;

use crate::widgets;

const CSS: &str = include_str!("../../../assets/deck.css");

pub fn apply_css() {
    let provider = gtk::CssProvider::new();
    provider.load_from_data(CSS);
    if let Some(display) = gtk::gdk::Display::default() {
        gtk::style_context_add_provider_for_display(
            &display,
            &provider,
            gtk::STYLE_PROVIDER_PRIORITY_APPLICATION,
        );
    }
}

pub fn widget_windows(
    app: &gtk::Application,
    settings: Rc<RefCell<Settings>>,
) -> Vec<gtk::ApplicationWindow> {
    let (livebox, netbox, devbox) = {
        let settings = settings.borrow();
        (
            settings.livebox.enabled,
            settings.netbox.enabled,
            settings.devbox.enabled,
        )
    };
    let mut windows = Vec::new();
    if livebox {
        windows.push(widgets::livebox::build(app, settings.clone()));
    }
    if netbox {
        windows.push(widgets::netbox::build(app, settings.clone()));
    }
    if devbox {
        windows.push(widgets::devbox::build(app, settings.clone()));
    }
    windows
}

pub fn search_window(app: &gtk::Application) -> (gtk::ApplicationWindow, gtk::Entry) {
    let window = deck_platform::surface::overlay_window(app, 640, 400);
    window.add_css_class("deck-surface");

    let content = gtk::Box::new(gtk::Orientation::Vertical, 8);
    content.set_margin_top(16);
    content.set_margin_bottom(16);
    content.set_margin_start(16);
    content.set_margin_end(16);

    let entry = gtk::Entry::builder()
        .placeholder_text("Search Deck…")
        .build();
    let list = gtk::ListBox::new();
    list.add_css_class("deck-list");
    let placeholder = gtk::Label::new(Some("Search providers arrive in L5"));
    placeholder.set_halign(gtk::Align::Start);
    let row = gtk::ListBoxRow::new();
    row.add_css_class("deck-row");
    row.set_child(Some(&placeholder));
    list.append(&row);

    content.append(&entry);
    content.append(&list);
    window.set_child(Some(&content));

    let controller = gtk::EventControllerKey::new();
    let window_for_key = window.clone();
    controller.connect_key_pressed(move |_, key, _, _| {
        if key == gtk::gdk::Key::Escape {
            window_for_key.hide();
            gtk::glib::Propagation::Stop
        } else {
            gtk::glib::Propagation::Proceed
        }
    });
    window.add_controller(controller);

    (window, entry)
}

pub fn toggle_search(window: &gtk::ApplicationWindow, entry: &gtk::Entry) {
    if window.is_visible() {
        window.hide();
    } else {
        window.present();
        entry.grab_focus();
    }
}

pub fn settings_window(
    app: &gtk::Application,
    paths: Paths,
    settings: Rc<RefCell<Settings>>,
) -> gtk::ApplicationWindow {
    let window = gtk::ApplicationWindow::builder()
        .application(app)
        .title("Deck Settings")
        .default_width(640)
        .default_height(560)
        .build();
    window.set_decorated(false);
    window.add_css_class("deck-surface");

    let notebook = gtk::Notebook::new();
    notebook.add_css_class("deck-notebook");

    let general = page();
    let autostart = gtk::CheckButton::with_label("Start Deck at login");
    autostart.set_active(settings.borrow().autostart);
    let paths_for_toggle = paths.clone();
    let settings_for_toggle = settings.clone();
    autostart.connect_toggled(move |check| {
        let active = check.is_active();
        {
            let mut current = settings_for_toggle.borrow_mut();
            current.autostart = active;
            let _ = current.save(&paths_for_toggle);
        }
        if active {
            let exec = std::env::current_exe().unwrap_or_else(|_| PathBuf::from("deck-gui"));
            let _ = deck_core::autostart::install(&exec, &paths_for_toggle);
        } else {
            let _ = deck_core::autostart::remove(&paths_for_toggle);
        }
    });
    general.append(&autostart);
    general.append(&caption(
        "A systemd user service can keep deckd running; this entry starts the GUI.",
    ));
    notebook.append_page(&general, Some(&tab("General")));

    let search = page();
    search.append(&caption("Spotlight-style panel shortcut"));
    let status = gtk::Label::new(Some(""));
    status.add_css_class("subtitle");
    status.set_halign(gtk::Align::Start);
    let install = gtk::Button::with_label("Install labwc shortcut (Super+Space)");
    let deck = std::env::current_exe()
        .ok()
        .and_then(|exe| exe.parent().map(|dir| dir.join("deck")))
        .unwrap_or_else(|| PathBuf::from("deck"));
    let status_for_click = status.clone();
    install.connect_clicked(move |_| {
        let command = format!("{} --toggle-search", deck.display());
        match deck_core::shortcut::install_labwc_shortcut(
            &command,
            deck_core::shortcut::DEFAULT_KEY,
        ) {
            Ok(path) => status_for_click.set_text(&format!("Installed in {}", path.display())),
            Err(error) => status_for_click.set_text(&format!("Could not install: {error}")),
        }
    });
    search.append(&install);
    search.append(&status);
    notebook.append_page(&search, Some(&tab("Search")));

    let credentials = page();
    credentials.append(&caption(
        "Secret Service when available, otherwise a 0600 file.",
    ));
    credentials.append(&caption(&format!(
        "Fallback: {}",
        paths.credentials_file().display()
    )));
    notebook.append_page(&credentials, Some(&tab("Credentials")));

    notebook.append_page(
        &scrolled(livebox_page(&paths, &settings)),
        Some(&tab("LiveBox")),
    );
    notebook.append_page(
        &scrolled(netbox_page(&paths, &settings)),
        Some(&tab("NetBox")),
    );
    notebook.append_page(
        &scrolled(devbox_page(&paths, &settings)),
        Some(&tab("DevBox")),
    );

    let header = gtk::Box::new(gtk::Orientation::Horizontal, 8);
    header.add_css_class("deck-header");
    header.set_margin_top(12);
    header.set_margin_bottom(8);
    header.set_margin_start(16);
    header.set_margin_end(16);
    let header_title = gtk::Label::new(Some("Deck Settings"));
    header_title.add_css_class("title");
    header_title.set_halign(gtk::Align::Start);
    header_title.set_hexpand(true);
    let close = gtk::Button::with_label("Close");
    close.add_css_class("deck-close");
    let window_for_close = window.clone();
    close.connect_clicked(move |_| window_for_close.hide());
    header.append(&header_title);
    header.append(&close);

    let handle = gtk::WindowHandle::new();
    handle.set_child(Some(&header));
    let root = gtk::Box::new(gtk::Orientation::Vertical, 0);
    root.append(&handle);
    root.append(&notebook);
    window.set_child(Some(&root));
    window
}

fn livebox_page(paths: &Paths, settings: &Rc<RefCell<Settings>>) -> gtk::Box {
    let page = page();
    page.append(&caption(
        "CPU, memory, disk and top processes. Size and visibility apply on restart.",
    ));
    let current = settings.borrow().livebox.clone();

    size_row(&page, current.size, paths, settings, |s, v| {
        s.livebox.size = v
    });
    toggle(
        &page,
        "Show LiveBox",
        current.enabled,
        paths,
        settings,
        |s, v| s.livebox.enabled = v,
    );
    toggle(
        &page,
        "Show CPU",
        current.show_cpu,
        paths,
        settings,
        |s, v| s.livebox.show_cpu = v,
    );
    toggle(
        &page,
        "Show memory",
        current.show_mem,
        paths,
        settings,
        |s, v| s.livebox.show_mem = v,
    );
    toggle(
        &page,
        "Show disk",
        current.show_disk,
        paths,
        settings,
        |s, v| s.livebox.show_disk = v,
    );
    toggle(
        &page,
        "Show GPU",
        current.show_gpu,
        paths,
        settings,
        |s, v| s.livebox.show_gpu = v,
    );
    toggle(
        &page,
        "Show processes",
        current.show_processes,
        paths,
        settings,
        |s, v| s.livebox.show_processes = v,
    );
    toggle(
        &page,
        "Show chart",
        current.show_chart,
        paths,
        settings,
        |s, v| s.livebox.show_chart = v,
    );
    spin(
        &page,
        "Process count",
        current.process_count as u64,
        1,
        10,
        1,
        paths,
        settings,
        |s, v| s.livebox.process_count = v as u8,
    );
    spin(
        &page,
        "Refresh (seconds)",
        current.refresh_seconds,
        5,
        120,
        5,
        paths,
        settings,
        |s, v| s.livebox.refresh_seconds = v,
    );
    spin(
        &page,
        "CPU warn",
        current.cpu_warn as u64,
        0,
        100,
        1,
        paths,
        settings,
        |s, v| s.livebox.cpu_warn = v as u8,
    );
    spin(
        &page,
        "CPU alarm",
        current.cpu_alarm as u64,
        0,
        100,
        1,
        paths,
        settings,
        |s, v| s.livebox.cpu_alarm = v as u8,
    );
    spin(
        &page,
        "MEM warn",
        current.mem_warn as u64,
        0,
        100,
        1,
        paths,
        settings,
        |s, v| s.livebox.mem_warn = v as u8,
    );
    spin(
        &page,
        "MEM alarm",
        current.mem_alarm as u64,
        0,
        100,
        1,
        paths,
        settings,
        |s, v| s.livebox.mem_alarm = v as u8,
    );
    spin(
        &page,
        "DISK warn",
        current.disk_warn as u64,
        0,
        100,
        1,
        paths,
        settings,
        |s, v| s.livebox.disk_warn = v as u8,
    );
    spin(
        &page,
        "DISK alarm",
        current.disk_alarm as u64,
        0,
        100,
        1,
        paths,
        settings,
        |s, v| s.livebox.disk_alarm = v as u8,
    );
    spin(
        &page,
        "GPU warn",
        current.gpu_warn as u64,
        0,
        100,
        1,
        paths,
        settings,
        |s, v| s.livebox.gpu_warn = v as u8,
    );
    spin(
        &page,
        "GPU alarm",
        current.gpu_alarm as u64,
        0,
        100,
        1,
        paths,
        settings,
        |s, v| s.livebox.gpu_alarm = v as u8,
    );
    page
}

fn netbox_page(paths: &Paths, settings: &Rc<RefCell<Settings>>) -> gtk::Box {
    let page = page();
    let current = settings.borrow().netbox.clone();
    page.append(&caption(
        "Per-interface traffic from /proc/net/dev. Empty interface means every interface.",
    ));
    size_row(&page, current.size, paths, settings, |s, v| {
        s.netbox.size = v
    });
    toggle(
        &page,
        "Show NetBox",
        current.enabled,
        paths,
        settings,
        |s, v| s.netbox.enabled = v,
    );
    text_field(
        &page,
        "Interface (optional)",
        &current.interface,
        "e.g. eth0",
        paths,
        settings,
        |s, v| s.netbox.interface = v,
    );
    spin(
        &page,
        "Interface count",
        current.interface_count as u64,
        1,
        10,
        1,
        paths,
        settings,
        |s, v| s.netbox.interface_count = v as u8,
    );
    spin(
        &page,
        "Refresh (seconds)",
        current.refresh_seconds,
        1,
        60,
        1,
        paths,
        settings,
        |s, v| s.netbox.refresh_seconds = v,
    );
    toggle(
        &page,
        "Show packet rates",
        current.show_packets,
        paths,
        settings,
        |s, v| s.netbox.show_packets = v,
    );
    toggle(
        &page,
        "Show chart (large)",
        current.show_chart,
        paths,
        settings,
        |s, v| s.netbox.show_chart = v,
    );
    spin(
        &page,
        "Warn (MB/s)",
        current.warn_mbps as u64,
        1,
        10000,
        1,
        paths,
        settings,
        |s, v| s.netbox.warn_mbps = v as u16,
    );
    spin(
        &page,
        "Alarm (MB/s)",
        current.alarm_mbps as u64,
        1,
        10000,
        1,
        paths,
        settings,
        |s, v| s.netbox.alarm_mbps = v as u16,
    );
    page
}

fn devbox_page(paths: &Paths, settings: &Rc<RefCell<Settings>>) -> gtk::Box {
    let page = page();
    let current = settings.borrow().devbox.clone();
    page.append(&caption(
        "Listening TCP ports from /proc and Docker containers from the docker CLI.",
    ));
    size_row(&page, current.size, paths, settings, |s, v| {
        s.devbox.size = v
    });
    toggle(
        &page,
        "Show DevBox",
        current.enabled,
        paths,
        settings,
        |s, v| s.devbox.enabled = v,
    );
    toggle(
        &page,
        "Show listening ports",
        current.show_ports,
        paths,
        settings,
        |s, v| s.devbox.show_ports = v,
    );
    toggle(
        &page,
        "Show containers",
        current.show_containers,
        paths,
        settings,
        |s, v| s.devbox.show_containers = v,
    );
    spin(
        &page,
        "Port count",
        current.port_count as u64,
        1,
        20,
        1,
        paths,
        settings,
        |s, v| s.devbox.port_count = v as u8,
    );
    spin(
        &page,
        "Container count",
        current.container_count as u64,
        1,
        20,
        1,
        paths,
        settings,
        |s, v| s.devbox.container_count = v as u8,
    );
    spin(
        &page,
        "Refresh (seconds)",
        current.refresh_seconds,
        2,
        120,
        1,
        paths,
        settings,
        |s, v| s.devbox.refresh_seconds = v,
    );
    page
}

fn page() -> gtk::Box {
    let page = gtk::Box::new(gtk::Orientation::Vertical, 8);
    page.add_css_class("deck-page");
    page.set_margin_top(16);
    page.set_margin_bottom(16);
    page.set_margin_start(16);
    page.set_margin_end(16);
    page
}

fn scrolled(page: gtk::Box) -> gtk::ScrolledWindow {
    let scrolled = gtk::ScrolledWindow::new();
    scrolled.set_policy(gtk::PolicyType::Never, gtk::PolicyType::Automatic);
    scrolled.set_vexpand(true);
    scrolled.set_child(Some(&page));
    scrolled
}

fn size_row(
    page: &gtk::Box,
    current: WidgetSize,
    paths: &Paths,
    settings: &Rc<RefCell<Settings>>,
    apply: fn(&mut Settings, WidgetSize),
) {
    let row = gtk::Box::new(gtk::Orientation::Horizontal, 8);
    let title = gtk::Label::new(Some("Size"));
    title.set_halign(gtk::Align::Start);
    title.set_hexpand(true);
    let combo = gtk::ComboBoxText::new();
    combo.append(Some("small"), "Small");
    combo.append(Some("medium"), "Medium");
    combo.append(Some("large"), "Large");
    combo.set_active_id(Some(match current {
        WidgetSize::Small => "small",
        WidgetSize::Medium => "medium",
        WidgetSize::Large => "large",
    }));
    let paths = paths.clone();
    let settings = settings.clone();
    combo.connect_changed(move |combo| {
        let size = match combo.active_id().as_deref() {
            Some("small") => WidgetSize::Small,
            Some("large") => WidgetSize::Large,
            _ => WidgetSize::Medium,
        };
        let mut current = settings.borrow_mut();
        apply(&mut current, size);
        let _ = current.save(&paths);
    });
    row.append(&title);
    row.append(&combo);
    page.append(&row);
}

fn tab(title: &str) -> gtk::Label {
    gtk::Label::new(Some(title))
}

fn caption(text: &str) -> gtk::Label {
    let label = gtk::Label::new(Some(text));
    label.set_halign(gtk::Align::Start);
    label.set_wrap(true);
    label.add_css_class("subtitle");
    label
}

fn toggle<F>(
    page: &gtk::Box,
    label: &str,
    active: bool,
    paths: &Paths,
    settings: &Rc<RefCell<Settings>>,
    apply: F,
) where
    F: Fn(&mut Settings, bool) + Copy + 'static,
{
    let check = gtk::CheckButton::with_label(label);
    check.set_active(active);
    let paths = paths.clone();
    let settings = settings.clone();
    check.connect_toggled(move |check| {
        let mut current = settings.borrow_mut();
        apply(&mut current, check.is_active());
        let _ = current.save(&paths);
    });
    page.append(&check);
}

#[allow(clippy::too_many_arguments)]
fn spin<F>(
    page: &gtk::Box,
    label: &str,
    value: u64,
    min: u64,
    max: u64,
    step: u64,
    paths: &Paths,
    settings: &Rc<RefCell<Settings>>,
    apply: F,
) where
    F: Fn(&mut Settings, u64) + Copy + 'static,
{
    let row = gtk::Box::new(gtk::Orientation::Horizontal, 8);
    let title = gtk::Label::new(Some(label));
    title.set_halign(gtk::Align::Start);
    title.set_hexpand(true);
    let spin = gtk::SpinButton::with_range(min as f64, max as f64, step as f64);
    spin.set_value(value as f64);
    let paths = paths.clone();
    let settings = settings.clone();
    spin.connect_value_changed(move |spin| {
        let mut current = settings.borrow_mut();
        apply(&mut current, spin.value() as u64);
        let _ = current.save(&paths);
    });
    row.append(&title);
    row.append(&spin);
    page.append(&row);
}

fn text_field<F>(
    page: &gtk::Box,
    label: &str,
    value: &str,
    placeholder: &str,
    paths: &Paths,
    settings: &Rc<RefCell<Settings>>,
    apply: F,
) where
    F: Fn(&mut Settings, String) + Copy + 'static,
{
    let title = gtk::Label::new(Some(label));
    title.set_halign(gtk::Align::Start);
    let entry = gtk::Entry::new();
    entry.set_text(value);
    entry.set_placeholder_text(Some(placeholder));
    let paths = paths.clone();
    let settings = settings.clone();
    entry.connect_changed(move |entry| {
        let mut current = settings.borrow_mut();
        apply(&mut current, entry.text().to_string());
        let _ = current.save(&paths);
    });
    page.append(&title);
    page.append(&entry);
}

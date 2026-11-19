use std::cell::RefCell;
use std::path::PathBuf;
use std::rc::Rc;
use std::time::Duration;

use deck_core::paths::Paths;
use deck_core::providers;
use deck_core::search as search_core;
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
    paths: Paths,
) -> Vec<gtk::ApplicationWindow> {
    let enabled = settings.borrow().clone();
    let mut widgets: Vec<(gtk::ApplicationWindow, i32)> = Vec::new();
    if enabled.livebox.enabled {
        widgets.push(widgets::livebox::build(app, settings.clone()));
    }
    if enabled.netbox.enabled {
        widgets.push(widgets::netbox::build(app, settings.clone()));
    }
    if enabled.devbox.enabled {
        widgets.push(widgets::devbox::build(app, settings.clone()));
    }
    if enabled.weather.enabled {
        widgets.push(widgets::weather::build(
            app,
            settings.clone(),
            paths.clone(),
        ));
    }
    if enabled.clock.enabled {
        widgets.push(widgets::clock::build(app, settings.clone()));
    }
    if enabled.git.enabled {
        widgets.push(widgets::git::build(app, settings.clone(), paths.clone()));
    }
    if enabled.market.enabled {
        widgets.push(widgets::market::build(app, settings.clone(), paths.clone()));
    }
    if enabled.openbox.enabled {
        widgets.push(widgets::open::build(app, settings.clone(), paths.clone()));
    }
    if enabled.ship.enabled {
        widgets.push(widgets::ship::build(app, settings.clone(), paths.clone()));
    }
    if enabled.tasks.enabled {
        widgets.push(widgets::tasks::build(app, settings.clone(), paths.clone()));
    }
    if enabled.prs.enabled {
        widgets.push(widgets::prs::build(app, settings.clone(), paths.clone()));
    }
    if enabled.logbox.enabled {
        widgets.push(widgets::logbox::build(app, settings.clone(), paths.clone()));
    }
    if enabled.metricbox.enabled {
        widgets.push(widgets::metricbox::build(
            app,
            settings.clone(),
            paths.clone(),
        ));
    }

    // Flow placement: three 320px columns. A full column moves to the next
    // monitor when one exists, so a multi-monitor desktop fills before it
    // stacks; on a single monitor it keeps stacking. Placement is automatic
    // and deterministic, so it survives restarts and monitor changes.
    let monitors: Vec<gtk::gdk::Monitor> = gtk::gdk::Display::default()
        .map(|display| {
            let model = display.monitors();
            (0..model.n_items())
                .filter_map(|index| model.item(index))
                .filter_map(|object| object.downcast::<gtk::gdk::Monitor>().ok())
                .collect()
        })
        .unwrap_or_default();
    let mut windows = Vec::new();
    let mut cursors = [48_i32; 3];
    let mut column = 0_usize;
    let mut monitor_index = 0_usize;
    for (window, height) in widgets {
        if cursors[column] + height > 752 {
            if column < 2 {
                column += 1;
            } else if monitor_index + 1 < monitors.len() {
                monitor_index += 1;
                column = 0;
                cursors = [48_i32; 3];
            }
        }
        let x = 24 + column as i32 * 332;
        let y = cursors[column];
        deck_platform::surface::place_on(&window, monitors.get(monitor_index), x, y);
        cursors[column] += height + 10;
        window.present();
        windows.push(window);
    }
    windows
}

pub fn search_window(
    app: &gtk::Application,
    paths: Paths,
    settings: Rc<RefCell<Settings>>,
) -> (gtk::ApplicationWindow, gtk::Entry) {
    let window = deck_platform::surface::overlay_window(app, 640, 420);
    window.add_css_class("deck-surface");

    let content = gtk::Box::new(gtk::Orientation::Vertical, 8);
    content.set_margin_top(16);
    content.set_margin_bottom(16);
    content.set_margin_start(16);
    content.set_margin_end(16);

    let entry = gtk::Entry::builder()
        .placeholder_text("Search Deck… (port, time, run, task, pr, log, metric, mkt)")
        .build();
    let list = gtk::ListBox::new();
    list.add_css_class("deck-list");
    list.set_selection_mode(gtk::SelectionMode::Single);
    let scrolled = gtk::ScrolledWindow::new();
    scrolled.set_policy(gtk::PolicyType::Never, gtk::PolicyType::Automatic);
    scrolled.set_vexpand(true);
    scrolled.set_child(Some(&list));

    content.append(&entry);
    content.append(&scrolled);
    window.set_child(Some(&content));

    let actions: Rc<RefCell<Vec<Option<search_core::SearchAction>>>> =
        Rc::new(RefCell::new(Vec::new()));
    let sampler = Rc::new(RefCell::new(deck_core::livebox::ProcessSampler::new()));
    render_search(
        &list,
        &actions,
        &[],
        Some("Type to search ports, clocks, processes, builds, tasks, logs and markets"),
    );

    // Generation counter instead of removing timers: removing a SourceId that
    // has already fired panics in glib, and an expired 180ms timer is harmless.
    let generation = Rc::new(std::cell::Cell::new(0_u64));
    let paths_for_change = paths.clone();
    let settings_for_change = settings.clone();
    let list_for_change = list.clone();
    let actions_for_change = actions.clone();
    let sampler_for_change = sampler.clone();
    entry.connect_changed(move |entry| {
        let ticket = generation.get() + 1;
        generation.set(ticket);
        let generation_for_timer = generation.clone();
        let text = entry.text().to_string();
        let paths = paths_for_change.clone();
        let settings = settings_for_change.clone();
        let list = list_for_change.clone();
        let actions = actions_for_change.clone();
        let sampler = sampler_for_change.clone();
        gtk::glib::timeout_add_local_once(Duration::from_millis(180), move || {
            if generation_for_timer.get() != ticket {
                return;
            }
            let sections = search_core::run(
                &search_inputs(&paths, &settings, &sampler),
                &text,
                deck_core::clockbox::now(),
            );
            render_search(&list, &actions, &sections, None);
        });
    });

    let window_for_activate = window.clone();
    let entry_for_activate = entry.clone();
    let actions_for_activate = actions.clone();
    let list_for_activate = list.clone();
    entry.connect_activate(move |_| {
        if let Some(row) = list_for_activate.selected_row() {
            activate_search_row(
                &window_for_activate,
                &entry_for_activate,
                &actions_for_activate,
                &row,
            );
        }
    });

    let window_for_row = window.clone();
    let entry_for_row = entry.clone();
    let actions_for_row = actions.clone();
    list.connect_row_activated(move |_, row| {
        activate_search_row(&window_for_row, &entry_for_row, &actions_for_row, row);
    });

    let controller = gtk::EventControllerKey::new();
    let window_for_key = window.clone();
    let list_for_key = list.clone();
    controller.connect_key_pressed(move |_, key, _, _| match key {
        gtk::gdk::Key::Escape => {
            window_for_key.hide();
            gtk::glib::Propagation::Stop
        }
        gtk::gdk::Key::Down => {
            move_search_selection(&list_for_key, 1);
            gtk::glib::Propagation::Stop
        }
        gtk::gdk::Key::Up => {
            move_search_selection(&list_for_key, -1);
            gtk::glib::Propagation::Stop
        }
        _ => gtk::glib::Propagation::Proceed,
    });
    entry.add_controller(controller);

    (window, entry)
}

fn search_inputs(
    paths: &Paths,
    settings: &Rc<RefCell<Settings>>,
    sampler: &Rc<RefCell<deck_core::livebox::ProcessSampler>>,
) -> search_core::SearchInputs {
    let mut inputs = search_core::SearchInputs {
        weather: deck_core::snapshot::read_payload(paths, "weather"),
        git: deck_core::snapshot::read_payload(paths, "gitbox"),
        market: deck_core::snapshot::read_payload(paths, "marketbox"),
        opencode: deck_core::snapshot::read_payload(paths, "opencode"),
        ship: deck_core::snapshot::read_payload(paths, "shipbox"),
        tasks: deck_core::snapshot::read_payload(paths, "taskbox"),
        prs: deck_core::snapshot::read_payload(paths, "prbox"),
        logbox: deck_core::snapshot::read_payload(paths, "logbox"),
        metricbox: deck_core::snapshot::read_payload(paths, "metricbox"),
        clock_ids: settings.borrow().clock.city_ids.clone(),
        ..search_core::SearchInputs::default()
    };
    inputs.processes = sampler.borrow_mut().sample(20).unwrap_or_default();
    inputs.interfaces = deck_core::netbox::interface_names();
    inputs.ports = deck_core::devbox::listening_ports().unwrap_or_default();
    inputs.containers = deck_core::devbox::docker_containers();
    inputs
}

fn render_search(
    list: &gtk::ListBox,
    actions: &Rc<RefCell<Vec<Option<search_core::SearchAction>>>>,
    sections: &[search_core::SearchSection],
    empty_text: Option<&str>,
) {
    while let Some(child) = list.first_child() {
        list.remove(&child);
    }
    let mut stored = Vec::new();
    if sections.is_empty() {
        let row = gtk::ListBoxRow::new();
        row.set_activatable(false);
        row.set_selectable(false);
        let label = gtk::Label::new(Some(empty_text.unwrap_or("No results")));
        label.add_css_class("subtitle");
        label.set_halign(gtk::Align::Start);
        label.set_margin_top(8);
        label.set_margin_bottom(8);
        row.set_child(Some(&label));
        list.append(&row);
        stored.push(None);
    } else {
        for section in sections {
            let header = gtk::ListBoxRow::new();
            header.set_activatable(false);
            header.set_selectable(false);
            let label = gtk::Label::new(Some(section.provider.title()));
            label.add_css_class("section");
            label.set_halign(gtk::Align::Start);
            label.set_margin_top(6);
            header.set_child(Some(&label));
            list.append(&header);
            stored.push(None);

            for result in &section.results {
                let row = gtk::ListBoxRow::new();
                let line = gtk::Box::new(gtk::Orientation::Vertical, 1);
                line.add_css_class("search-row");
                let title = gtk::Label::new(Some(&result.title));
                title.add_css_class("search-title");
                title.set_halign(gtk::Align::Start);
                title.set_ellipsize(gtk::pango::EllipsizeMode::End);
                let subtitle = gtk::Label::new(Some(&result.subtitle));
                subtitle.add_css_class("subtitle");
                subtitle.set_halign(gtk::Align::Start);
                subtitle.set_ellipsize(gtk::pango::EllipsizeMode::End);
                line.append(&title);
                line.append(&subtitle);
                row.set_child(Some(&line));
                list.append(&row);
                stored.push(Some(result.action.clone()));
            }
        }
    }
    *actions.borrow_mut() = stored;
    select_first_search_row(list);
}

fn select_first_search_row(list: &gtk::ListBox) {
    let mut index = 0;
    while let Some(row) = list.row_at_index(index) {
        if row.is_activatable() {
            list.select_row(Some(&row));
            return;
        }
        index += 1;
    }
}

fn move_search_selection(list: &gtk::ListBox, delta: i32) {
    let current = list
        .selected_row()
        .map(|row| row.index())
        .unwrap_or(if delta > 0 { -1 } else { 0 });
    let mut count = 0;
    while list.row_at_index(count).is_some() {
        count += 1;
    }
    let mut index = current + delta;
    while index >= 0 && index < count {
        if let Some(row) = list.row_at_index(index) {
            if row.is_activatable() {
                list.select_row(Some(&row));
                return;
            }
        }
        index += delta;
    }
}

fn activate_search_row(
    window: &gtk::ApplicationWindow,
    entry: &gtk::Entry,
    actions: &Rc<RefCell<Vec<Option<search_core::SearchAction>>>>,
    row: &gtk::ListBoxRow,
) {
    let index = row.index() as usize;
    let Some(Some(action)) = actions.borrow().get(index).cloned() else {
        return;
    };
    match action {
        search_core::SearchAction::Copy(text) => {
            entry.clipboard().set_text(&text);
        }
        search_core::SearchAction::Open(url) => {
            let _ = gtk::gio::AppInfo::launch_default_for_uri(
                &url,
                None::<&gtk::gio::AppLaunchContext>,
            );
        }
    }
    window.hide();
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
        .default_width(760)
        .default_height(600)
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
    if deck_core::credentials::CredentialStore::detect(&paths).kind() == "file-0600" {
        general.append(&caption(
            "No system keyring (secret-tool) was found. Tokens are stored in a 0600 file; install libsecret-tools and sign in to a keyring to use Secret Service.",
        ));
    }
    surface_row(&general, settings.borrow().surface_mode, &paths, &settings);
    if let Some(last) = deck_core::diag::read(&paths.cache_dir, "last-error.log") {
        let line = last.lines().next().unwrap_or("unknown error");
        general.append(&caption(&format!("Last crash: {line}")));
    }
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

    let credentials = credentials_page(&paths, &settings);
    notebook.append_page(&credentials, Some(&tab("Credentials")));

    notebook.append_page(&widgets_page(&paths, &settings), Some(&tab("Widgets")));

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

fn widgets_page(paths: &Paths, settings: &Rc<RefCell<Settings>>) -> gtk::Box {
    let root = gtk::Box::new(gtk::Orientation::Horizontal, 0);
    let list = gtk::ListBox::new();
    list.add_css_class("widget-list");
    list.set_width_request(150);
    let stack = gtk::Stack::new();
    stack.set_hexpand(true);
    stack.set_vexpand(true);

    let pages = vec![
        ("LiveBox", livebox_page(paths, settings)),
        ("NetBox", netbox_page(paths, settings)),
        ("DevBox", devbox_page(paths, settings)),
        ("Weather", weather_page(paths, settings)),
        ("Clock", clock_page(paths, settings)),
        ("Git", git_page(paths, settings)),
        ("Market", market_page(paths, settings)),
        ("Open", open_page(paths, settings)),
        ("Ship", ship_page(paths, settings)),
        ("Tasks", tasks_page(paths, settings)),
        ("Pull requests", prs_page(paths, settings)),
        ("Logs", logbox_page(paths, settings)),
        ("Metrics", metricbox_page(paths, settings)),
    ];
    let mut names = Vec::new();
    for (name, page) in pages {
        names.push(name.to_string());
        let label = gtk::Label::new(Some(name));
        label.set_halign(gtk::Align::Start);
        label.set_xalign(0.0);
        label.set_margin_top(6);
        label.set_margin_bottom(6);
        label.set_margin_start(8);
        let row = gtk::ListBoxRow::new();
        row.set_child(Some(&label));
        list.append(&row);
        stack.add_named(&scrolled(page), Some(name));
    }

    let stack_for_select = stack.clone();
    let names_for_select = names.clone();
    list.connect_row_selected(move |_, row| {
        if let Some(row) = row {
            if let Some(name) = names_for_select.get(row.index() as usize) {
                stack_for_select.set_visible_child_name(name);
            }
        }
    });
    if let Some(row) = list.row_at_index(0) {
        list.select_row(Some(&row));
    }
    root.append(&list);
    root.append(&stack);
    root
}

fn weather_page(paths: &Paths, settings: &Rc<RefCell<Settings>>) -> gtk::Box {
    let page = page();
    let current = settings.borrow().weather.clone();
    page.append(&caption(
        "wttr.in current conditions and a three-day forecast. No account is needed.",
    ));
    size_row(&page, current.size, paths, settings, |s, v| {
        s.weather.size = v
    });
    toggle(
        &page,
        "Show WeatherBox",
        current.enabled,
        paths,
        settings,
        |s, v| s.weather.enabled = v,
    );
    text_field(
        &page,
        "Location (empty geolocates)",
        &current.location,
        "e.g. Amsterdam",
        paths,
        settings,
        |s, v| s.weather.location = v,
    );
    toggle(
        &page,
        "Fahrenheit",
        current.units_fahrenheit,
        paths,
        settings,
        |s, v| s.weather.units_fahrenheit = v,
    );
    toggle(
        &page,
        "Show forecast",
        current.show_forecast,
        paths,
        settings,
        |s, v| s.weather.show_forecast = v,
    );
    page
}

fn clock_page(paths: &Paths, settings: &Rc<RefCell<Settings>>) -> gtk::Box {
    let page = page();
    let current = settings.borrow().clock.clone();
    page.append(&caption(
        "IANA zone IDs, one per entry. `local` follows this machine.",
    ));
    size_row(&page, current.size, paths, settings, |s, v| {
        s.clock.size = v
    });
    toggle(
        &page,
        "Show ClockBox",
        current.enabled,
        paths,
        settings,
        |s, v| s.clock.enabled = v,
    );
    list_field(
        &page,
        "Cities",
        &current.city_ids,
        "local, Europe/Amsterdam, Asia/Tokyo",
        paths,
        settings,
        |s, v| s.clock.city_ids = v,
    );
    text_field(
        &page,
        "Main city (small face, optional)",
        &current.main_city_id,
        "empty = first non-local city",
        paths,
        settings,
        |s, v| s.clock.main_city_id = v,
    );
    toggle(
        &page,
        "Show relative day",
        current.show_relative_day,
        paths,
        settings,
        |s, v| s.clock.show_relative_day = v,
    );
    toggle(
        &page,
        "Show offset",
        current.show_offset,
        paths,
        settings,
        |s, v| s.clock.show_offset = v,
    );
    page
}

fn git_page(paths: &Paths, settings: &Rc<RefCell<Settings>>) -> gtk::Box {
    let page = page();
    let current = settings.borrow().git.clone();
    page.append(&caption(
        "Scans repo roots for .git directories and reads git log locally.",
    ));
    size_row(&page, current.size, paths, settings, |s, v| s.git.size = v);
    toggle(
        &page,
        "Show GitBox",
        current.enabled,
        paths,
        settings,
        |s, v| s.git.enabled = v,
    );
    list_field(
        &page,
        "Repo roots",
        &current.repo_paths,
        "~/dev, ~/work",
        paths,
        settings,
        |s, v| s.git.repo_paths = v,
    );
    spin(
        &page,
        "Scan depth",
        current.scan_depth as u64,
        1,
        6,
        1,
        paths,
        settings,
        |s, v| s.git.scan_depth = v as u8,
    );
    toggle(
        &page,
        "Show chart",
        current.show_chart,
        paths,
        settings,
        |s, v| s.git.show_chart = v,
    );
    toggle(
        &page,
        "Show repos (large)",
        current.show_repos,
        paths,
        settings,
        |s, v| s.git.show_repos = v,
    );
    spin(
        &page,
        "Repo count",
        current.repo_count as u64,
        1,
        10,
        1,
        paths,
        settings,
        |s, v| s.git.repo_count = v as u8,
    );
    page
}

fn market_page(paths: &Paths, settings: &Rc<RefCell<Settings>>) -> gtk::Box {
    let page = page();
    let current = settings.borrow().market.clone();
    page.append(&caption(
        "Crypto, stocks, gold and fiat. Prices are converted to the display currency.",
    ));
    size_row(&page, current.size, paths, settings, |s, v| {
        s.market.size = v
    });
    toggle(
        &page,
        "Show MarketBox",
        current.enabled,
        paths,
        settings,
        |s, v| s.market.enabled = v,
    );
    list_field(
        &page,
        "Symbols",
        &current.symbols,
        "BTC, ETH, GOLD, AAPL, EUR",
        paths,
        settings,
        |s, v| s.market.symbols = v,
    );
    currency_row(&page, current.display_currency, paths, settings);
    spin(
        &page,
        "Ticker count (large)",
        current.ticker_count as u64,
        1,
        12,
        1,
        paths,
        settings,
        |s, v| s.market.ticker_count = v as u8,
    );
    toggle(
        &page,
        "Show day change",
        current.show_day_change,
        paths,
        settings,
        |s, v| s.market.show_day_change = v,
    );
    page
}

fn open_page(paths: &Paths, settings: &Rc<RefCell<Settings>>) -> gtk::Box {
    let page = page();
    let current = settings.borrow().openbox.clone();
    page.append(&caption(
        "Reads the local opencode SQLite database; no token is needed.",
    ));
    size_row(&page, current.size, paths, settings, |s, v| {
        s.openbox.size = v
    });
    toggle(
        &page,
        "Show OpenBox",
        current.enabled,
        paths,
        settings,
        |s, v| s.openbox.enabled = v,
    );
    toggle(
        &page,
        "Show models",
        current.show_models,
        paths,
        settings,
        |s, v| s.openbox.show_models = v,
    );
    toggle(
        &page,
        "Show tools",
        current.show_tools,
        paths,
        settings,
        |s, v| s.openbox.show_tools = v,
    );
    toggle(
        &page,
        "Show sessions (large)",
        current.show_sessions,
        paths,
        settings,
        |s, v| s.openbox.show_sessions = v,
    );
    spin(
        &page,
        "Model count",
        current.model_count as u64,
        1,
        6,
        1,
        paths,
        settings,
        |s, v| s.openbox.model_count = v as u8,
    );
    spin(
        &page,
        "Tool count",
        current.tool_count as u64,
        1,
        6,
        1,
        paths,
        settings,
        |s, v| s.openbox.tool_count = v as u8,
    );
    spin(
        &page,
        "Session count",
        current.session_count as u64,
        1,
        6,
        1,
        paths,
        settings,
        |s, v| s.openbox.session_count = v as u8,
    );
    page
}

fn ship_page(paths: &Paths, settings: &Rc<RefCell<Settings>>) -> gtk::Box {
    let page = page();
    let current = settings.borrow().ship.clone();
    page.append(&caption(
        "GitHub Actions runs for explicit repos. Add a GitHub token in Credentials.",
    ));
    size_row(&page, current.size, paths, settings, |s, v| s.ship.size = v);
    toggle(
        &page,
        "Show ShipBox",
        current.enabled,
        paths,
        settings,
        |s, v| s.ship.enabled = v,
    );
    list_field(
        &page,
        "Repos",
        &current.repos,
        "owner/repo, owner/other",
        paths,
        settings,
        |s, v| s.ship.repos = v,
    );
    spin(
        &page,
        "Run count",
        current.run_count as u64,
        2,
        8,
        1,
        paths,
        settings,
        |s, v| s.ship.run_count = v as u8,
    );
    toggle(
        &page,
        "Show runs",
        current.show_list,
        paths,
        settings,
        |s, v| s.ship.show_list = v,
    );
    page
}

fn tasks_page(paths: &Paths, settings: &Rc<RefCell<Settings>>) -> gtk::Box {
    let page = page();
    let current = settings.borrow().tasks.clone();
    page.append(&caption(
        "Azure DevOps work items assigned to you. Add an Azure PAT in Credentials.",
    ));
    size_row(&page, current.size, paths, settings, |s, v| {
        s.tasks.size = v
    });
    toggle(
        &page,
        "Show TaskBox",
        current.enabled,
        paths,
        settings,
        |s, v| s.tasks.enabled = v,
    );
    text_field(
        &page,
        "Organization",
        &current.organization,
        "e.g. contoso",
        paths,
        settings,
        |s, v| s.tasks.organization = v,
    );
    text_field(
        &page,
        "Project",
        &current.project,
        "e.g. Manifold",
        paths,
        settings,
        |s, v| s.tasks.project = v,
    );
    text_field(
        &page,
        "WIQL (empty = assigned open items)",
        &current.query,
        "SELECT [System.Id] FROM WorkItems …",
        paths,
        settings,
        |s, v| s.tasks.query = v,
    );
    spin(
        &page,
        "Task count",
        current.task_count as u64,
        1,
        20,
        1,
        paths,
        settings,
        |s, v| s.tasks.task_count = v as u8,
    );
    toggle(
        &page,
        "Show lane legend",
        current.show_legend,
        paths,
        settings,
        |s, v| s.tasks.show_legend = v,
    );
    toggle(
        &page,
        "Show list",
        current.show_list,
        paths,
        settings,
        |s, v| s.tasks.show_list = v,
    );
    page
}

fn prs_page(paths: &Paths, settings: &Rc<RefCell<Settings>>) -> gtk::Box {
    let page = page();
    let current = settings.borrow().prs.clone();
    page.append(&caption(
        "GitHub and Azure DevOps review queues. Azure uses the Tasks organization and project.",
    ));
    size_row(&page, current.size, paths, settings, |s, v| s.prs.size = v);
    toggle(
        &page,
        "Show PRBox",
        current.enabled,
        paths,
        settings,
        |s, v| s.prs.enabled = v,
    );
    spin(
        &page,
        "PR count",
        current.pr_count as u64,
        3,
        12,
        1,
        paths,
        settings,
        |s, v| s.prs.pr_count = v as u8,
    );
    toggle(
        &page,
        "Show list",
        current.show_list,
        paths,
        settings,
        |s, v| s.prs.show_list = v,
    );
    page
}

fn logbox_page(paths: &Paths, settings: &Rc<RefCell<Settings>>) -> gtk::Box {
    let page = page();
    let current = settings.borrow().logbox.clone();
    page.append(&caption(
        "Elastic error/warn counts, 24h trend, services and recent lines. Add an Elastic API key in Credentials.",
    ));
    size_row(&page, current.size, paths, settings, |s, v| {
        s.logbox.size = v
    });
    toggle(
        &page,
        "Show LogBox",
        current.enabled,
        paths,
        settings,
        |s, v| s.logbox.enabled = v,
    );
    text_field(
        &page,
        "Elastic base URL",
        &current.base_url,
        "https://es.example.com",
        paths,
        settings,
        |s, v| s.logbox.base_url = v,
    );
    text_field(
        &page,
        "Environment",
        &current.environment,
        "prd, stg or logs-manifold-prd",
        paths,
        settings,
        |s, v| s.logbox.environment = v,
    );
    text_field(
        &page,
        "Service (optional)",
        &current.service,
        "empty = all services",
        paths,
        settings,
        |s, v| s.logbox.service = v,
    );
    text_mode_row(&page, current.text_mode, paths, settings);
    let catalog_row = gtk::Box::new(gtk::Orientation::Horizontal, 8);
    let load = gtk::Button::with_label("Load catalogs");
    let catalog = caption("");
    catalog_row.append(&load);
    catalog_row.append(&catalog);
    page.append(&catalog_row);
    let paths_for_catalog = paths.clone();
    let log_for_catalog = settings.borrow().logbox.clone();
    let catalog_for_click = catalog.clone();
    load.connect_clicked(move |_| {
        let paths = paths_for_catalog.clone();
        let log = log_for_catalog.clone();
        let status = catalog_for_click.clone();
        verify_async(&status, move || {
            let Ok(key) = providers::require_token(&paths, "elastic") else {
                return "Add an Elastic API key first".into();
            };
            match deck_core::logbox::environment_catalog(&log.base_url, &key) {
                Err(error) => format!("Catalog failed: {}", error.message()),
                Ok(environments) => {
                    match deck_core::logbox::service_catalog(&log.base_url, &key, &log.environment)
                    {
                        Ok(services) => format!(
                            "Environments: {} · Services: {}",
                            environments
                                .iter()
                                .take(5)
                                .cloned()
                                .collect::<Vec<_>>()
                                .join(", "),
                            services
                                .iter()
                                .take(8)
                                .cloned()
                                .collect::<Vec<_>>()
                                .join(", ")
                        ),
                        Err(error) => {
                            format!("Environments loaded; services failed: {}", error.message())
                        }
                    }
                }
            }
        });
    });
    spin(
        &page,
        "Small window (minutes)",
        u64::from(current.small_minutes),
        5,
        1440,
        5,
        paths,
        settings,
        |s, v| s.logbox.small_minutes = v as u16,
    );
    spin(
        &page,
        "Large window (minutes)",
        u64::from(current.large_minutes),
        15,
        10080,
        15,
        paths,
        settings,
        |s, v| s.logbox.large_minutes = v as u16,
    );
    toggle(
        &page,
        "Show trend",
        current.show_trend,
        paths,
        settings,
        |s, v| s.logbox.show_trend = v,
    );
    page
}

fn metricbox_page(paths: &Paths, settings: &Rc<RefCell<Settings>>) -> gtk::Box {
    let page = page();
    let current = settings.borrow().metricbox.clone();
    page.append(&caption(
        "Grafana fleet, host, power, agents and alerts. Add a Grafana token in Credentials.",
    ));
    size_row(&page, current.size, paths, settings, |s, v| {
        s.metricbox.size = v
    });
    toggle(
        &page,
        "Show MetricBox",
        current.enabled,
        paths,
        settings,
        |s, v| s.metricbox.enabled = v,
    );
    text_field(
        &page,
        "Grafana base URL",
        &current.base_url,
        "https://grafana.example.com",
        paths,
        settings,
        |s, v| s.metricbox.base_url = v,
    );
    metric_face_row(&page, current.face, paths, settings);
    text_field(
        &page,
        "Host (single-host face)",
        &current.host,
        "e.g. x201",
        paths,
        settings,
        |s, v| s.metricbox.host = v,
    );
    spin(
        &page,
        "Rate (cents/kWh)",
        u64::from(current.rate_per_kwh_cents),
        0,
        100,
        1,
        paths,
        settings,
        |s, v| s.metricbox.rate_per_kwh_cents = v as u16,
    );
    toggle(
        &page,
        "Show CPU",
        current.show_cpu,
        paths,
        settings,
        |s, v| s.metricbox.show_cpu = v,
    );
    toggle(
        &page,
        "Show RAM",
        current.show_ram,
        paths,
        settings,
        |s, v| s.metricbox.show_ram = v,
    );
    toggle(
        &page,
        "Show disk",
        current.show_disk,
        paths,
        settings,
        |s, v| s.metricbox.show_disk = v,
    );
    toggle(
        &page,
        "Show GPU",
        current.show_gpu,
        paths,
        settings,
        |s, v| s.metricbox.show_gpu = v,
    );
    toggle(
        &page,
        "Show power",
        current.show_power,
        paths,
        settings,
        |s, v| s.metricbox.show_power = v,
    );
    page
}

fn surface_row(
    page: &gtk::Box,
    current: deck_core::settings::SurfaceMode,
    paths: &Paths,
    settings: &Rc<RefCell<Settings>>,
) {
    let row = gtk::Box::new(gtk::Orientation::Horizontal, 8);
    let title = gtk::Label::new(Some("Widget surface (restart)"));
    title.set_halign(gtk::Align::Start);
    title.set_hexpand(true);
    let combo = gtk::ComboBoxText::new();
    for (id, label) in [
        ("auto", "Auto-detect"),
        ("layershell", "Layer shell"),
        ("x11", "X11 desktop"),
        ("dashboard", "Dashboard window"),
    ] {
        combo.append(Some(id), label);
    }
    combo.set_active_id(Some(match current {
        deck_core::settings::SurfaceMode::Auto => "auto",
        deck_core::settings::SurfaceMode::LayerShell => "layershell",
        deck_core::settings::SurfaceMode::X11 => "x11",
        deck_core::settings::SurfaceMode::Dashboard => "dashboard",
    }));
    let paths = paths.clone();
    let settings = settings.clone();
    combo.connect_changed(move |combo| {
        let mode = match combo.active_id().as_deref() {
            Some("layershell") => deck_core::settings::SurfaceMode::LayerShell,
            Some("x11") => deck_core::settings::SurfaceMode::X11,
            Some("dashboard") => deck_core::settings::SurfaceMode::Dashboard,
            _ => deck_core::settings::SurfaceMode::Auto,
        };
        let mut current = settings.borrow_mut();
        current.surface_mode = mode;
        let _ = current.save(&paths);
    });
    row.append(&title);
    row.append(&combo);
    page.append(&row);
}

fn text_mode_row(
    page: &gtk::Box,
    current: deck_core::settings::LogTextMode,
    paths: &Paths,
    settings: &Rc<RefCell<Settings>>,
) {
    let row = gtk::Box::new(gtk::Orientation::Horizontal, 8);
    let title = gtk::Label::new(Some("Recent lines"));
    title.set_halign(gtk::Align::Start);
    title.set_hexpand(true);
    let combo = gtk::ComboBoxText::new();
    for (id, label) in [
        ("templates", "Templates only"),
        ("latest", "Latest message"),
        ("full", "Full lines"),
    ] {
        combo.append(Some(id), label);
    }
    combo.set_active_id(Some(match current {
        deck_core::settings::LogTextMode::Templates => "templates",
        deck_core::settings::LogTextMode::Latest => "latest",
        deck_core::settings::LogTextMode::Full => "full",
    }));
    let paths = paths.clone();
    let settings = settings.clone();
    combo.connect_changed(move |combo| {
        let mode = match combo.active_id().as_deref() {
            Some("latest") => deck_core::settings::LogTextMode::Latest,
            Some("full") => deck_core::settings::LogTextMode::Full,
            _ => deck_core::settings::LogTextMode::Templates,
        };
        let mut current = settings.borrow_mut();
        current.logbox.text_mode = mode;
        let _ = current.save(&paths);
    });
    row.append(&title);
    row.append(&combo);
    page.append(&row);
}

fn metric_face_row(
    page: &gtk::Box,
    current: deck_core::settings::MetricBoxFace,
    paths: &Paths,
    settings: &Rc<RefCell<Settings>>,
) {
    let row = gtk::Box::new(gtk::Orientation::Horizontal, 8);
    let title = gtk::Label::new(Some("Face"));
    title.set_halign(gtk::Align::Start);
    title.set_hexpand(true);
    let combo = gtk::ComboBoxText::new();
    for (id, label) in [
        ("fleet", "Fleet health"),
        ("host", "Single host"),
        ("power", "Power"),
        ("agents", "Top agents"),
        ("alerts", "Alerts"),
    ] {
        combo.append(Some(id), label);
    }
    combo.set_active_id(Some(match current {
        deck_core::settings::MetricBoxFace::Fleet => "fleet",
        deck_core::settings::MetricBoxFace::Host => "host",
        deck_core::settings::MetricBoxFace::Power => "power",
        deck_core::settings::MetricBoxFace::Agents => "agents",
        deck_core::settings::MetricBoxFace::Alerts => "alerts",
    }));
    let paths = paths.clone();
    let settings = settings.clone();
    combo.connect_changed(move |combo| {
        let face = match combo.active_id().as_deref() {
            Some("host") => deck_core::settings::MetricBoxFace::Host,
            Some("power") => deck_core::settings::MetricBoxFace::Power,
            Some("agents") => deck_core::settings::MetricBoxFace::Agents,
            Some("alerts") => deck_core::settings::MetricBoxFace::Alerts,
            _ => deck_core::settings::MetricBoxFace::Fleet,
        };
        let mut current = settings.borrow_mut();
        current.metricbox.face = face;
        let _ = current.save(&paths);
    });
    row.append(&title);
    row.append(&combo);
    page.append(&row);
}

fn credentials_page(paths: &Paths, settings: &Rc<RefCell<Settings>>) -> gtk::Box {
    let page = page();
    page.append(&caption(
        "Secret Service when available, otherwise a 0600 file. Tokens are read by deckd.",
    ));
    page.append(&caption(&format!(
        "Store: {} · fallback {}",
        deck_core::credentials::CredentialStore::detect(paths).kind(),
        paths.credentials_file().display()
    )));
    credential_row(
        &page,
        paths,
        settings,
        "GitHub token",
        "github",
        VerifyKind::Github,
    );
    credential_row(
        &page,
        paths,
        settings,
        "Azure DevOps PAT",
        "azure",
        VerifyKind::Azure,
    );
    credential_row(
        &page,
        paths,
        settings,
        "Elastic API key",
        "elastic",
        VerifyKind::Elastic,
    );
    credential_row(
        &page,
        paths,
        settings,
        "Grafana token",
        "grafana",
        VerifyKind::Grafana,
    );
    opencode_row(&page);
    page
}

#[derive(Clone, Copy)]
enum VerifyKind {
    Github,
    Azure,
    Elastic,
    Grafana,
}

fn credential_row(
    page: &gtk::Box,
    paths: &Paths,
    settings: &Rc<RefCell<Settings>>,
    label: &str,
    id: &str,
    kind: VerifyKind,
) {
    widgets::section(page, label);
    let row = gtk::Box::new(gtk::Orientation::Horizontal, 6);
    let entry = gtk::Entry::new();
    entry.set_visibility(false);
    entry.set_input_purpose(gtk::InputPurpose::Password);
    entry.set_placeholder_text(Some("stored token is not shown"));
    entry.set_hexpand(true);
    let save = gtk::Button::with_label("Save");
    let delete = gtk::Button::with_label("Delete");
    let verify = gtk::Button::with_label("Verify");
    row.append(&entry);
    row.append(&save);
    row.append(&delete);
    row.append(&verify);
    page.append(&row);
    let status = caption("");
    page.append(&status);

    let paths_for_save = paths.clone();
    let id_owned = id.to_owned();
    let status_for_save = status.clone();
    let entry_for_save = entry.clone();
    save.connect_clicked(move |_| {
        let value = entry_for_save.text().to_string();
        if value.trim().is_empty() {
            status_for_save.set_text("Enter a token first");
            return;
        }
        let store = deck_core::credentials::CredentialStore::detect(&paths_for_save);
        match store.write(&id_owned, value.trim()) {
            Ok(()) => {
                entry_for_save.set_text("");
                status_for_save.set_text("Saved");
            }
            Err(error) => status_for_save.set_text(&format!("Could not save: {error}")),
        }
    });

    let paths_for_delete = paths.clone();
    let id_owned = id.to_owned();
    let status_for_delete = status.clone();
    delete.connect_clicked(move |_| {
        let store = deck_core::credentials::CredentialStore::detect(&paths_for_delete);
        match store.delete(&id_owned) {
            Ok(()) => status_for_delete.set_text("Deleted"),
            Err(error) => status_for_delete.set_text(&format!("Could not delete: {error}")),
        }
    });

    let paths_for_verify = paths.clone();
    let settings_for_verify = settings.clone();
    let status_for_verify = status.clone();
    verify.connect_clicked(move |_| {
        let paths = paths_for_verify.clone();
        let org = settings_for_verify.borrow().tasks.organization.clone();
        let log_base = settings_for_verify.borrow().logbox.base_url.clone();
        let metric_base = settings_for_verify.borrow().metricbox.base_url.clone();
        verify_async(&status_for_verify, move || match kind {
            VerifyKind::Github => verify_github(&paths),
            VerifyKind::Azure => verify_azure(&paths, &org),
            VerifyKind::Elastic => verify_elastic(&paths, &log_base),
            VerifyKind::Grafana => verify_grafana(&paths, &metric_base),
        });
    });
}

fn opencode_row(page: &gtk::Box) {
    widgets::section(page, "opencode database");
    let paths = deck_core::openbox::default_db_path();
    page.append(&caption(&paths.display().to_string()));
    let row = gtk::Box::new(gtk::Orientation::Horizontal, 6);
    let verify = gtk::Button::with_label("Check");
    row.append(&verify);
    page.append(&row);
    let status = caption("");
    page.append(&status);
    verify.connect_clicked(move |_| {
        let status = status.clone();
        verify_async(&status, || match deck_core::openbox::load() {
            Ok(Some(snapshot)) => format!(
                "{} sessions in the last 24h, {} total tokens",
                snapshot.sessions, snapshot.total_input
            ),
            Ok(None) => "opencode database not found".into(),
            Err(error) => format!("Could not read: {error}"),
        });
    });
}

fn verify_async<F>(label: &gtk::Label, work: F)
where
    F: FnOnce() -> String + Send + 'static,
{
    label.set_text("Checking…");
    let (sender, receiver) = std::sync::mpsc::channel();
    std::thread::spawn(move || {
        let _ = sender.send(work());
    });
    let label = label.clone();
    gtk::glib::timeout_add_local(Duration::from_millis(100), move || {
        match receiver.try_recv() {
            Ok(message) => {
                label.set_text(&message);
                gtk::glib::ControlFlow::Break
            }
            Err(std::sync::mpsc::TryRecvError::Empty) => gtk::glib::ControlFlow::Continue,
            Err(std::sync::mpsc::TryRecvError::Disconnected) => {
                label.set_text("Verification failed");
                gtk::glib::ControlFlow::Break
            }
        }
    });
}

fn verify_github(paths: &Paths) -> String {
    let Ok(token) = providers::require_token(paths, "github") else {
        return "No GitHub token stored".into();
    };
    match providers::get(
        "https://api.github.com/user",
        &[
            ("Authorization", &format!("Bearer {token}")),
            ("Accept", "application/vnd.github+json"),
            ("X-GitHub-Api-Version", "2022-11-28"),
        ],
    ) {
        Ok(body) => {
            let login = serde_json::from_str::<serde_json::Value>(&body)
                .ok()
                .and_then(|json| {
                    json.get("login")
                        .and_then(|value| value.as_str())
                        .map(str::to_owned)
                })
                .unwrap_or_default();
            if login.is_empty() {
                "Token answered, but no login was returned".into()
            } else {
                format!("Token works for {login}")
            }
        }
        Err(error) => format!("Failed: {}", error.message()),
    }
}

fn verify_azure(paths: &Paths, organization: &str) -> String {
    if organization.trim().is_empty() {
        return "Set the Tasks organization first".into();
    }
    let Ok(token) = providers::require_token(paths, "azure") else {
        return "No Azure PAT stored".into();
    };
    let auth = providers::basic_auth("", &token);
    match providers::get(
        &format!(
            "https://dev.azure.com/{}/_apis/connectionData?api-version=7.0",
            organization.trim()
        ),
        &[("Authorization", &auth), ("Accept", "application/json")],
    ) {
        Ok(body) => {
            let name = serde_json::from_str::<serde_json::Value>(&body)
                .ok()
                .and_then(|json| {
                    json.get("authenticatedUser")
                        .and_then(|user| user.get("providerDisplayName"))
                        .and_then(|value| value.as_str())
                        .map(str::to_owned)
                })
                .unwrap_or_default();
            if name.is_empty() {
                "PAT works".into()
            } else {
                format!("PAT works for {name}")
            }
        }
        Err(error) => format!("Failed: {}", error.message()),
    }
}

fn verify_elastic(paths: &Paths, base: &str) -> String {
    let Some(base) = providers::normalize_base(base) else {
        return "Set the LogBox base URL first".into();
    };
    let Ok(token) = providers::require_token(paths, "elastic") else {
        return "No Elastic API key stored".into();
    };
    match providers::get(
        &format!("{base}/_cluster/health"),
        &[
            ("Authorization", &format!("ApiKey {token}")),
            ("Accept", "application/json"),
        ],
    ) {
        Ok(body) => {
            let status = serde_json::from_str::<serde_json::Value>(&body)
                .ok()
                .and_then(|json| {
                    json.get("status")
                        .and_then(|value| value.as_str())
                        .map(str::to_owned)
                })
                .unwrap_or_default();
            if status.is_empty() {
                "Cluster answered".into()
            } else {
                format!("Cluster is {status}")
            }
        }
        Err(error) => format!("Failed: {}", error.message()),
    }
}

fn verify_grafana(paths: &Paths, base: &str) -> String {
    let Some(base) = providers::normalize_base(base) else {
        return "Set the MetricBox base URL first".into();
    };
    let Ok(token) = providers::require_token(paths, "grafana") else {
        return "No Grafana token stored".into();
    };
    match providers::get(
        &format!("{base}/api/health"),
        &[
            ("Authorization", &format!("Bearer {token}")),
            ("Accept", "application/json"),
        ],
    ) {
        Ok(body) => {
            let version = serde_json::from_str::<serde_json::Value>(&body)
                .ok()
                .and_then(|json| {
                    json.get("version")
                        .and_then(|value| value.as_str())
                        .map(str::to_owned)
                })
                .unwrap_or_default();
            if version.is_empty() {
                "Grafana answered".into()
            } else {
                format!("Grafana {version} answers")
            }
        }
        Err(error) => format!("Failed: {}", error.message()),
    }
}

fn currency_row(
    page: &gtk::Box,
    current: deck_core::market::MarketCurrency,
    paths: &Paths,
    settings: &Rc<RefCell<Settings>>,
) {
    let row = gtk::Box::new(gtk::Orientation::Horizontal, 8);
    let title = gtk::Label::new(Some("Display currency"));
    title.set_halign(gtk::Align::Start);
    title.set_hexpand(true);
    let combo = gtk::ComboBoxText::new();
    for currency in [
        deck_core::market::MarketCurrency::Usd,
        deck_core::market::MarketCurrency::Eur,
        deck_core::market::MarketCurrency::Cad,
        deck_core::market::MarketCurrency::Aed,
        deck_core::market::MarketCurrency::Irt,
        deck_core::market::MarketCurrency::Irr,
    ] {
        combo.append(Some(currency.label()), currency.label());
    }
    combo.set_active_id(Some(current.label()));
    let paths = paths.clone();
    let settings = settings.clone();
    combo.connect_changed(move |combo| {
        let Some(currency) = combo
            .active_id()
            .and_then(|id| deck_core::market::MarketCurrency::from_label(&id))
        else {
            return;
        };
        let mut current = settings.borrow_mut();
        current.market.display_currency = currency;
        let _ = current.save(&paths);
    });
    row.append(&title);
    row.append(&combo);
    page.append(&row);
}

fn list_field(
    page: &gtk::Box,
    label: &str,
    values: &[String],
    placeholder: &str,
    paths: &Paths,
    settings: &Rc<RefCell<Settings>>,
    apply: fn(&mut Settings, Vec<String>),
) {
    text_field(
        page,
        label,
        &values.join(", "),
        placeholder,
        paths,
        settings,
        move |settings, text| {
            let values = text
                .split([',', '\n'])
                .map(str::trim)
                .filter(|value| !value.is_empty())
                .map(str::to_owned)
                .collect();
            apply(settings, values);
        },
    );
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

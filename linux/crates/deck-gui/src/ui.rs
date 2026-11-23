use std::cell::{Cell, RefCell};
use std::path::PathBuf;
use std::rc::Rc;
use std::sync::mpsc;
use std::time::{Duration, Instant};

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

thread_local! {
    static WIDGET_WINDOWS: RefCell<Vec<(String, i32, gtk::ApplicationWindow)>> =
        const { RefCell::new(Vec::new()) };
}

fn widget_enabled(settings: &Settings, title: &str) -> bool {
    match title {
        "LiveBox" => settings.livebox.enabled,
        "CalBox" => settings.calbox.enabled,
        "ClipBox" => settings.clipbox.enabled,
        "BatBox" => settings.batbox.enabled,
        "NetBox" => settings.netbox.enabled,
        "DevBox" => settings.devbox.enabled,
        "Weather" => settings.weather.enabled,
        "Clock" => settings.clock.enabled,
        "Git" => settings.git.enabled,
        "Market" => settings.market.enabled,
        "Open" => settings.openbox.enabled,
        "Ship" => settings.ship.enabled,
        "Tasks" => settings.tasks.enabled,
        "Pull requests" => settings.prs.enabled,
        "Logs" => settings.logbox.enabled,
        "Metrics" => settings.metricbox.enabled,
        _ => true,
    }
}

/// Places the enabled widgets and applies visibility immediately after a
/// settings switch. Hidden widgets do not reserve space in the flow.
pub fn refresh_widget_visibility(settings: &Rc<RefCell<Settings>>) {
    let monitors: Vec<gtk::gdk::Monitor> = gtk::gdk::Display::default()
        .map(|display| {
            let model = display.monitors();
            (0..model.n_items())
                .filter_map(|index| model.item(index))
                .filter_map(|object| object.downcast::<gtk::gdk::Monitor>().ok())
                .collect()
        })
        .unwrap_or_default();
    let current = settings.borrow();
    let mut cursors = [48_i32; 3];
    let mut column = 0_usize;
    let mut monitor_index = 0_usize;
    WIDGET_WINDOWS.with(|windows| {
        for (title, height, window) in windows.borrow().iter() {
            if !widget_enabled(&current, title) {
                window.hide();
                continue;
            }
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
            let saved = current.positions.get(title).copied();
            let (x, y) = saved
                .map(|position| (position.x, position.y))
                .unwrap_or((x, y));
            deck_platform::surface::place_on(window, monitors.get(monitor_index), x, y);
            cursors[column] += height + 10;
            window.present();
        }
    });
}

pub fn widget_windows(
    app: &gtk::Application,
    settings: Rc<RefCell<Settings>>,
    paths: Paths,
) -> Vec<gtk::ApplicationWindow> {
    // Build every widget once so the settings window can show and hide them
    // without a restart. Visibility is applied after placement.
    let mut build = settings.borrow().clone();
    build.livebox.enabled = true;
    build.calbox.enabled = true;
    build.clipbox.enabled = true;
    build.batbox.enabled = true;
    build.netbox.enabled = true;
    build.devbox.enabled = true;
    build.weather.enabled = true;
    build.clock.enabled = true;
    build.git.enabled = true;
    build.market.enabled = true;
    build.openbox.enabled = true;
    build.ship.enabled = true;
    build.tasks.enabled = true;
    build.prs.enabled = true;
    build.logbox.enabled = true;
    build.metricbox.enabled = true;
    let enabled = build;
    let mut widgets: Vec<(gtk::ApplicationWindow, i32)> = Vec::new();
    if enabled.livebox.enabled {
        widgets.push(widgets::livebox::build(app, settings.clone()));
    }
    if enabled.calbox.enabled {
        widgets.push(widgets::calbox::build(app, settings.clone(), paths.clone()));
    }
    if enabled.clipbox.enabled {
        widgets.push(widgets::clipbox::build(
            app,
            settings.clone(),
            paths.clone(),
        ));
    }
    if enabled.batbox.enabled {
        widgets.push(widgets::batbox::build(app, settings.clone(), paths.clone()));
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

    // Flow placement is applied by the registry so disabled widgets do not
    // reserve a column slot and toggling one immediately reflows the rest.
    let mut windows = Vec::new();
    WIDGET_WINDOWS.with(|registry| registry.borrow_mut().clear());
    for (window, height) in widgets {
        let key = window
            .title()
            .map(|title| title.to_string())
            .unwrap_or_default();
        WIDGET_WINDOWS.with(|registry| registry.borrow_mut().push((key, height, window.clone())));
        windows.push(window);
    }
    refresh_widget_visibility(&settings);
    windows
}

/// A minimal top row that moves a widget without adding a macOS-less title.
pub fn widget_drag_bar(
    window: &gtk::ApplicationWindow,
    settings: Rc<RefCell<Settings>>,
) -> gtk::Widget {
    let bar = gtk::Box::new(gtk::Orientation::Horizontal, 0);
    bar.set_hexpand(true);
    let grip = gtk::Label::new(Some("⠿"));
    grip.add_css_class("search-grip");
    grip.set_halign(gtk::Align::End);
    grip.set_hexpand(true);
    bar.append(&grip);
    movable_header(window, &bar, settings, 28)
}

/// Wraps a header so it moves the window on every backend: margins on a
/// layer surface, a client-side window handle otherwise.
pub fn movable_header<W>(
    window: &gtk::ApplicationWindow,
    header: &W,
    settings: Rc<RefCell<Settings>>,
    drag_zone: i32,
) -> gtk::Widget
where
    W: IsA<gtk::Widget> + Clone + 'static,
{
    if deck_platform::surface::uses_layer_shell() {
        make_draggable(window, header, settings, drag_zone);
        header.clone().upcast()
    } else {
        let handle = gtk::WindowHandle::new();
        handle.set_child(Some(header));
        handle.upcast()
    }
}

/// Makes a layer-surface widget/search window draggable by a handle. The
/// position is written to settings on drop and restored on the next start.
pub fn make_draggable(
    window: &gtk::ApplicationWindow,
    handle: &impl IsA<gtk::Widget>,
    settings: Rc<RefCell<Settings>>,
    drag_zone: i32,
) {
    if !deck_platform::surface::uses_layer_shell() {
        return;
    }
    struct Drag {
        target: (i32, i32),
        applied: (i32, i32),
        max: (i32, i32),
        last_dx: f64,
        last_dy: f64,
        last_window: (i32, i32),
        active: bool,
    }

    handle.set_cursor_from_name(Some("grab"));
    let drag = gtk::GestureDrag::new();
    drag.set_propagation_phase(gtk::PropagationPhase::Capture);
    let state: Rc<RefCell<Option<Drag>>> = Rc::new(RefCell::new(None));
    let ticking = Rc::new(Cell::new(false));
    // Gesture offsets are window-relative. As the window follows the pointer,
    // its local coordinates move too, which halves the apparent motion and
    // makes dragging feel sticky. Add the window movement since the last event
    // back in so the card tracks the pointer 1:1.
    let apply_pointer_delta = |drag: &mut Drag, dx: f64, dy: f64| {
        let local_dx = dx - drag.last_dx;
        let local_dy = dy - drag.last_dy;
        let window_dx = f64::from(drag.applied.0 - drag.last_window.0);
        let window_dy = f64::from(drag.applied.1 - drag.last_window.1);
        drag.target = (
            (f64::from(drag.target.0) + local_dx + window_dx).round() as i32,
            (f64::from(drag.target.1) + local_dy + window_dy).round() as i32,
        );
        drag.target.0 = drag.target.0.clamp(0, drag.max.0);
        drag.target.1 = drag.target.1.clamp(0, drag.max.1);
        drag.last_dx = dx;
        drag.last_dy = dy;
        drag.last_window = drag.applied;
    };

    let window_for_begin = window.clone();
    let handle_for_begin = handle.clone();
    let state_for_begin = state.clone();
    let ticking_for_begin = ticking.clone();
    drag.connect_drag_begin(move |_, _, y| {
        if y > f64::from(drag_zone) {
            *state_for_begin.borrow_mut() = None;
            return;
        }
        let origin = deck_platform::surface::position(&window_for_begin);
        *state_for_begin.borrow_mut() = Some(Drag {
            target: origin,
            applied: origin,
            max: deck_platform::surface::max_position(&window_for_begin),
            last_dx: 0.0,
            last_dy: 0.0,
            last_window: origin,
            active: true,
        });
        handle_for_begin.set_cursor_from_name(Some("grabbing"));
        if !ticking_for_begin.replace(true) {
            let state = state_for_begin.clone();
            let ticking = ticking_for_begin.clone();
            let tick_window = window_for_begin.clone();
            window_for_begin.add_tick_callback(move |_, _| {
                let mut slot = state.borrow_mut();
                let Some(drag) = slot.as_mut() else {
                    ticking.set(false);
                    return gtk::glib::ControlFlow::Break;
                };
                if drag.target != drag.applied {
                    deck_platform::surface::move_to_raw(&tick_window, drag.target.0, drag.target.1);
                    drag.applied = drag.target;
                }
                if drag.active {
                    gtk::glib::ControlFlow::Continue
                } else {
                    *slot = None;
                    ticking.set(false);
                    gtk::glib::ControlFlow::Break
                }
            });
        }
    });

    let state_for_update = state.clone();
    drag.connect_drag_update(move |_, dx, dy| {
        if let Some(drag) = state_for_update.borrow_mut().as_mut() {
            apply_pointer_delta(drag, dx, dy);
        }
    });

    let window_for_end = window.clone();
    let handle_for_end = handle.clone();
    let settings_for_end = settings;
    let state_for_end = state;
    drag.connect_drag_end(move |_, dx, dy| {
        let mut slot = state_for_end.borrow_mut();
        let Some(drag) = slot.as_mut() else {
            return;
        };
        apply_pointer_delta(drag, dx, dy);
        let target = drag.target;
        deck_platform::surface::move_to_raw(&window_for_end, target.0, target.1);
        drag.applied = target;
        drag.active = false;
        handle_for_end.set_cursor_from_name(Some("grab"));
        let key = window_for_end
            .title()
            .map(|title| title.to_string())
            .unwrap_or_default();
        let mut current = settings_for_end.borrow_mut();
        current.positions.insert(
            key,
            deck_core::settings::WindowPosition {
                x: target.0,
                y: target.1,
            },
        );
        let _ = current.save(&Paths::from_env());
    });
    window.add_controller(drag);
}

pub fn search_window(
    app: &gtk::Application,
    paths: Paths,
    settings: Rc<RefCell<Settings>>,
) -> (gtk::ApplicationWindow, gtk::Entry) {
    let window = deck_platform::surface::overlay_window(app, 640, 360);
    window.add_css_class("search-window");

    let content = gtk::Box::new(gtk::Orientation::Vertical, 4);
    content.add_css_class("search-card");
    if !deck_platform::surface::uses_layer_shell() {
        content.add_css_class("search-card-opaque");
    }
    content.set_margin_top(8);
    content.set_margin_bottom(8);
    content.set_margin_start(8);
    content.set_margin_end(8);

    let header = gtk::Box::new(gtk::Orientation::Horizontal, 4);
    let grip = gtk::Label::new(Some("⠿"));
    grip.add_css_class("search-grip");
    grip.set_halign(gtk::Align::End);
    grip.set_hexpand(true);
    header.append(&grip);
    content.append(&movable_header(&window, &header, settings.clone(), 26));

    let entry = gtk::Entry::builder()
        .placeholder_text("Search Deck…")
        .build();
    entry.add_css_class("search-entry");
    entry.set_margin_start(14);
    entry.set_margin_end(14);
    let list = gtk::ListBox::new();
    list.add_css_class("deck-list");
    list.set_selection_mode(gtk::SelectionMode::Single);
    let scrolled = gtk::ScrolledWindow::new();
    scrolled.set_policy(gtk::PolicyType::Never, gtk::PolicyType::Automatic);
    scrolled.set_vexpand(true);
    scrolled.set_child(Some(&list));

    content.append(&entry);
    let divider = gtk::Separator::new(gtk::Orientation::Horizontal);
    divider.add_css_class("search-divider");
    divider.set_margin_start(12);
    divider.set_margin_end(12);
    content.append(&divider);
    scrolled.set_margin_start(6);
    scrolled.set_margin_end(6);
    scrolled.set_margin_bottom(6);
    content.append(&scrolled);
    window.set_child(Some(&content));

    let width = 640;
    let screen_width = gtk::gdk::Display::default()
        .and_then(|display| display.monitors().item(0))
        .and_then(|object| object.downcast::<gtk::gdk::Monitor>().ok())
        .map(|monitor| monitor.geometry().width())
        .unwrap_or(width);
    let (x, y) = settings
        .borrow()
        .positions
        .get("Deck Search")
        .map(|position| (position.x, position.y))
        .unwrap_or(((screen_width - width).max(0) / 2, 100));
    deck_platform::surface::place(&window, x, y);

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
    let generation = Rc::new(Cell::new(0_u64));
    let remote_cache = Rc::new(RefCell::new(search_core::RemoteSearchCache::default()));
    let task_blocked: Rc<Cell<Option<Instant>>> = Rc::new(Cell::new(None));
    let pr_blocked: Rc<Cell<Option<Instant>>> = Rc::new(Cell::new(None));
    let log_blocked: Rc<Cell<Option<Instant>>> = Rc::new(Cell::new(None));
    let metric_blocked: Rc<Cell<Option<Instant>>> = Rc::new(Cell::new(None));
    let last_local: Rc<RefCell<Vec<search_core::SearchSection>>> =
        Rc::new(RefCell::new(Vec::new()));
    let (remote_tx, remote_rx) = mpsc::channel::<RemoteSearchMessage>();
    let paths_for_change = paths.clone();
    let settings_for_change = settings.clone();
    let list_for_change = list.clone();
    let actions_for_change = actions.clone();
    let sampler_for_change = sampler.clone();
    let generation_for_change = generation.clone();
    let cache_for_change = remote_cache.clone();
    let task_blocked_for_change = task_blocked.clone();
    let pr_blocked_for_change = pr_blocked.clone();
    let log_blocked_for_change = log_blocked.clone();
    let metric_blocked_for_change = metric_blocked.clone();
    let local_for_change = last_local.clone();
    let tx_for_change = remote_tx.clone();
    entry.connect_changed(move |entry| {
        let ticket = generation_for_change.get() + 1;
        generation_for_change.set(ticket);
        let generation_for_timer = generation_for_change.clone();
        let text = entry.text().to_string();
        let paths = paths_for_change.clone();
        let settings = settings_for_change.clone();
        let list = list_for_change.clone();
        let actions = actions_for_change.clone();
        let sampler = sampler_for_change.clone();
        let cache = cache_for_change.clone();
        let task_blocked = task_blocked_for_change.clone();
        let pr_blocked = pr_blocked_for_change.clone();
        let log_blocked = log_blocked_for_change.clone();
        let metric_blocked = metric_blocked_for_change.clone();
        let local = local_for_change.clone();
        let tx = tx_for_change.clone();
        gtk::glib::timeout_add_local_once(Duration::from_millis(180), move || {
            if generation_for_timer.get() != ticket {
                return;
            }
            let sections = search_core::run(
                &search_inputs(&paths, &settings, &sampler),
                &text,
                deck_core::clockbox::now(),
            );
            *local.borrow_mut() = sections.clone();
            render_search(&list, &actions, &sections, None);
            schedule_remote_search(
                &text,
                ticket,
                cache,
                task_blocked,
                pr_blocked,
                log_blocked,
                metric_blocked,
                local,
                list,
                actions,
                paths,
                settings,
                tx,
            );
        });
    });

    let poll_generation = generation.clone();
    let poll_cache = remote_cache.clone();
    let poll_task_blocked = task_blocked.clone();
    let poll_pr_blocked = pr_blocked.clone();
    let poll_log_blocked = log_blocked.clone();
    let poll_metric_blocked = metric_blocked.clone();
    let poll_local = last_local.clone();
    let poll_list = list.clone();
    let poll_actions = actions.clone();
    gtk::glib::timeout_add_local(Duration::from_millis(150), move || {
        while let Ok(message) = remote_rx.try_recv() {
            if poll_generation.get() != message.ticket {
                continue;
            }
            match message.result {
                Ok(results) => {
                    poll_cache
                        .borrow_mut()
                        .put(message.key, results.clone(), Instant::now());
                    if !results.is_empty() {
                        let mut sections = poll_local.borrow().clone();
                        merge_remote_sections(&mut sections, results);
                        render_search(&poll_list, &poll_actions, &sections, None);
                    }
                }
                Err(providers::FetchError::RateLimited) => {
                    let until = Some(Instant::now() + search_core::REMOTE_SEARCH_BACKOFF);
                    if message.key.starts_with("task:") {
                        poll_task_blocked.set(until);
                    } else if message.key.starts_with("log:") {
                        poll_log_blocked.set(until);
                    } else if message.key.starts_with("metric:") {
                        poll_metric_blocked.set(until);
                    } else {
                        poll_pr_blocked.set(until);
                    }
                }
                Err(_) => {}
            }
        }
        gtk::glib::ControlFlow::Continue
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

struct RemoteSearchMessage {
    ticket: u64,
    key: String,
    result: Result<Vec<search_core::SearchResult>, providers::FetchError>,
}

fn merge_remote_sections(
    sections: &mut Vec<search_core::SearchSection>,
    remote: Vec<search_core::SearchResult>,
) {
    let Some(provider) = remote.first().map(|result| result.provider) else {
        return;
    };
    if let Some(section) = sections
        .iter_mut()
        .find(|section| section.provider == provider)
    {
        for result in remote {
            if !section
                .results
                .iter()
                .any(|existing| existing.id == result.id)
            {
                section.results.push(result);
            }
        }
        section.results.sort_by(|left, right| {
            right
                .score
                .cmp(&left.score)
                .then_with(|| left.title.cmp(&right.title))
        });
        section.results.truncate(10);
        return;
    }
    let mut remote = remote;
    remote.sort_by(|left, right| {
        right
            .score
            .cmp(&left.score)
            .then_with(|| left.title.cmp(&right.title))
    });
    remote.truncate(10);
    let position = sections
        .iter()
        .position(|section| section.provider >= provider)
        .unwrap_or(sections.len());
    sections.insert(
        position,
        search_core::SearchSection {
            provider,
            results: remote,
        },
    );
}

enum RemoteRequest {
    Tasks {
        token_id: String,
        organization: String,
        project: String,
        kind: Option<search_core::WorkItemKind>,
    },
    Prs {
        github_token_id: String,
        azure_token_id: String,
        organization: String,
        project: String,
    },
    Logs {
        token_id: String,
        base: String,
        index: String,
    },
    Metrics {
        token_id: String,
        base: String,
    },
}

#[allow(clippy::too_many_arguments)]
fn schedule_remote_search(
    text: &str,
    ticket: u64,
    cache: Rc<RefCell<search_core::RemoteSearchCache>>,
    task_blocked: Rc<Cell<Option<Instant>>>,
    pr_blocked: Rc<Cell<Option<Instant>>>,
    log_blocked: Rc<Cell<Option<Instant>>>,
    metric_blocked: Rc<Cell<Option<Instant>>>,
    local: Rc<RefCell<Vec<search_core::SearchSection>>>,
    list: gtk::ListBox,
    actions: Rc<RefCell<Vec<Option<search_core::SearchAction>>>>,
    paths: Paths,
    settings: Rc<RefCell<Settings>>,
    tx: mpsc::Sender<RemoteSearchMessage>,
) {
    let query = search_core::parse(text);
    if query.text.chars().count() < search_core::REMOTE_SEARCH_FLOOR {
        return;
    }
    let tasks = settings.borrow().tasks.clone();
    let request = match query.scope {
        None | Some(search_core::SearchProvider::Task) => {
            if settings
                .borrow()
                .search
                .disabled
                .iter()
                .any(|id| id == "task")
            {
                return;
            }
            let current = settings.borrow();
            let (token_id, organization, project) = current.azure_account(&tasks.account_id);
            let token_id = token_id.to_owned();
            let organization = organization.to_owned();
            let project = project.to_owned();
            drop(current);
            if !tasks.enabled || organization.trim().is_empty() || project.trim().is_empty() {
                return;
            }
            RemoteRequest::Tasks {
                token_id,
                organization,
                project,
                kind: query.work_item_kind,
            }
        }
        Some(search_core::SearchProvider::Pr) => {
            let enabled = settings.borrow().prs.enabled
                && !settings
                    .borrow()
                    .search
                    .disabled
                    .iter()
                    .any(|id| id == "pr");
            if !enabled {
                return;
            }
            let current = settings.borrow();
            let (token_id, organization, project) =
                current.azure_account(&current.prs.azure_account_id);
            let azure_token_id = token_id.to_owned();
            let organization = organization.to_owned();
            let project = project.to_owned();
            let (github_token_id, _, _, _) =
                current.selected_account("github", &current.prs.github_account_id);
            drop(current);
            RemoteRequest::Prs {
                github_token_id,
                azure_token_id,
                organization,
                project,
            }
        }
        Some(search_core::SearchProvider::Metric) => {
            let metric = settings.borrow().metricbox.clone();
            let (token_id, _, _, server) = settings
                .borrow()
                .selected_account("grafana", &metric.account_id);
            let base = if server.is_empty() {
                metric.base_url.clone()
            } else {
                server
            };
            let enabled = metric.enabled
                && !base.trim().is_empty()
                && !settings
                    .borrow()
                    .search
                    .disabled
                    .iter()
                    .any(|id| id == "metric");
            if !enabled {
                return;
            }
            RemoteRequest::Metrics { token_id, base }
        }
        Some(search_core::SearchProvider::Log) => {
            let log = settings.borrow().logbox.clone();
            let enabled = log.enabled
                && !log.base_url.trim().is_empty()
                && !settings
                    .borrow()
                    .search
                    .disabled
                    .iter()
                    .any(|id| id == "log");
            if !enabled {
                return;
            }
            let (token_id, _, _, server) = settings
                .borrow()
                .selected_account("elastic", &log.account_id);
            RemoteRequest::Logs {
                token_id,
                base: if server.is_empty() {
                    log.base_url.clone()
                } else {
                    server
                },
                index: deck_core::logbox::normalize_environment(&log.environment),
            }
        }
        _ => return,
    };
    let blocked = match &request {
        RemoteRequest::Tasks { .. } => task_blocked,
        RemoteRequest::Prs { .. } => pr_blocked,
        RemoteRequest::Logs { .. } => log_blocked,
        RemoteRequest::Metrics { .. } => metric_blocked,
    };
    if let Some(until) = blocked.get() {
        if until > Instant::now() {
            return;
        }
    }
    let key = match &request {
        RemoteRequest::Tasks { kind, .. } => {
            format!("task:{:?}:{}", kind, query.text.to_lowercase())
        }
        RemoteRequest::Prs { .. } => format!("pr:{}", query.text.to_lowercase()),
        RemoteRequest::Logs { .. } => format!("log:{}", query.text.to_lowercase()),
        RemoteRequest::Metrics { .. } => format!("metric:{}", query.text.to_lowercase()),
    };
    if let Some(cached) = cache.borrow_mut().get(&key, Instant::now()) {
        if !cached.is_empty() {
            let mut sections = local.borrow().clone();
            merge_remote_sections(&mut sections, cached);
            render_search(&list, &actions, &sections, None);
        }
        return;
    }
    let text = query.text;
    std::thread::spawn(move || {
        let result = match request {
            RemoteRequest::Tasks {
                token_id,
                organization,
                project,
                kind,
            } => providers::require_token(&paths, &token_id).and_then(|token| {
                search_core::remote_task_search(&organization, &project, &token, &text, kind)
            }),
            RemoteRequest::Logs {
                token_id,
                base,
                index,
            } => providers::require_token(&paths, &token_id).and_then(|token| {
                deck_core::logbox::search_messages(&base, &token, &index, &text, 10)
                    .map(|hits| search_core::remote_log_results(&hits, &text, &base, &index))
            }),
            RemoteRequest::Metrics { token_id, base } => {
                providers::require_token(&paths, &token_id).and_then(|token| {
                    deck_core::metricbox::search_dashboards(&base, &token, &text)
                        .map(|hits| search_core::remote_metric_results(&hits, &text, &base))
                })
            }
            RemoteRequest::Prs {
                github_token_id,
                azure_token_id,
                organization,
                project,
            } => {
                let github = providers::token(&paths, &github_token_id).ok().flatten();
                let azure = providers::token(&paths, &azure_token_id).ok().flatten();
                if github.is_none() && azure.is_none() {
                    Err(providers::FetchError::NotConfigured)
                } else {
                    search_core::remote_pr_search(
                        deck_core::prs::PrSources {
                            github_token: github.as_deref(),
                            azure_token: azure.as_deref(),
                            azure_org: &organization,
                            azure_project: &project,
                            limit: 12,
                            show_review_state: false,
                        },
                        &text,
                    )
                }
            }
        };
        let _ = tx.send(RemoteSearchMessage {
            ticket,
            key,
            result,
        });
    });
}

fn search_inputs(
    paths: &Paths,
    settings: &Rc<RefCell<Settings>>,
    sampler: &Rc<RefCell<deck_core::livebox::ProcessSampler>>,
) -> search_core::SearchInputs {
    let mut inputs = search_core::SearchInputs {
        weather: deck_core::snapshot::read_payload(paths, "weather"),
        calbox: deck_core::snapshot::read_payload(paths, "calbox"),
        clipbox: deck_core::clipbox::load(paths),
        git: deck_core::snapshot::read_payload(paths, "gitbox"),
        market: deck_core::snapshot::read_payload(paths, "marketbox"),
        opencode: deck_core::snapshot::read_payload(paths, "opencode"),
        ship: deck_core::snapshot::read_payload(paths, "shipbox"),
        tasks: deck_core::snapshot::read_payload(paths, "taskbox"),
        prs: deck_core::snapshot::read_payload(paths, "prbox"),
        logbox: deck_core::snapshot::read_payload(paths, "logbox"),
        metricbox: deck_core::snapshot::read_payload(paths, "metricbox"),
        clock_ids: settings.borrow().clock.city_ids.clone(),
        disabled: settings.borrow().search.disabled.clone(),
        log_base: {
            let current = settings.borrow();
            let (_, _, _, server) = current.selected_account("elastic", &current.logbox.account_id);
            Some(if server.is_empty() {
                current.logbox.base_url.clone()
            } else {
                server
            })
        },
        log_index: Some(deck_core::logbox::normalize_environment(
            &settings.borrow().logbox.environment,
        )),
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
            let label = gtk::Label::new(Some(&section.provider.title().to_uppercase()));
            label.add_css_class("search-section");
            label.set_halign(gtk::Align::Start);
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
        deck_platform::surface::center_overlay(window);
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

    let general = page();
    general.add_css_class("deck-page-cards");
    let refresh = form_card(&general, "BACKGROUND REFRESH");
    let autostart_row = gtk::Box::new(gtk::Orientation::Horizontal, 8);
    autostart_row.add_css_class("form-row");
    let autostart_label = gtk::Label::new(Some("Start Deck at login"));
    autostart_label.set_halign(gtk::Align::Start);
    autostart_label.set_hexpand(true);
    let autostart = gtk::Switch::new();
    autostart.set_active(settings.borrow().autostart);
    autostart.set_valign(gtk::Align::Center);
    let paths_for_toggle = paths.clone();
    let settings_for_toggle = settings.clone();
    autostart.connect_active_notify(move |switch| {
        let active = switch.is_active();
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
    autostart_row.append(&autostart_label);
    autostart_row.append(&autostart);
    refresh.append(&autostart_row);
    refresh.append(&caption(
        "A systemd user service can keep deckd running; this entry starts the GUI.",
    ));
    if deck_core::credentials::CredentialStore::detect(&paths).kind() == "file-0600" {
        refresh.append(&caption(
            "No system keyring (secret-tool) was found. Tokens are stored in a 0600 file; install libsecret-tools and sign in to a keyring to use Secret Service.",
        ));
    }
    let surface = form_card(&general, "SURFACE");
    surface_row(&surface, settings.borrow().surface_mode, &paths, &settings);
    if let Some(last) = deck_core::diag::read(&paths.cache_dir, "last-error.log") {
        let line = last.lines().next().unwrap_or("unknown error");
        surface.append(&caption(&format!("Last crash: {line}")));
    }
    let update_row = gtk::Box::new(gtk::Orientation::Horizontal, 8);
    let check_update = gtk::Button::with_label("Check for updates");
    let update_status = caption(&format!("Deck {}", env!("CARGO_PKG_VERSION")));
    update_row.append(&check_update);
    update_row.append(&update_status);
    surface.append(&update_row);
    let update_status_for_click = update_status.clone();
    check_update.connect_clicked(move |_| {
        let status = update_status_for_click.clone();
        verify_async(&status, || match deck_core::update::latest() {
            Ok(release) => {
                if deck_core::update::is_newer(env!("CARGO_PKG_VERSION"), &release.tag) {
                    format!("{} is available — {}", release.tag, release.url)
                } else {
                    format!("Deck {} is up to date", env!("CARGO_PKG_VERSION"))
                }
            }
            Err(error) => format!("Update check failed: {}", error.message()),
        });
    });

    let search = page();
    search.add_css_class("deck-page-cards");
    let shortcut = form_card(&search, "SHORTCUT");
    shortcut.append(&caption("Spotlight-style panel shortcut"));
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
    shortcut.append(&install);
    shortcut.append(&status);
    let sources = form_card(&search, "SOURCES");
    let disabled = settings.borrow().search.disabled.clone();
    for provider in search_core::SearchProvider::ALL {
        let id = provider.id();
        toggle(
            &sources,
            provider.settings_title(),
            !disabled.iter().any(|entry| entry == id),
            &paths,
            &settings,
            move |current, enabled| {
                current.search.disabled.retain(|entry| entry != id);
                if !enabled {
                    current.search.disabled.push(id.to_owned());
                }
            },
        );
    }

    let credentials = credentials_page(&paths, &settings);

    let body = gtk::Box::new(gtk::Orientation::Horizontal, 0);
    let sidebar = gtk::ListBox::new();
    sidebar.add_css_class("settings-sidebar");
    sidebar.set_width_request(190);
    let stack = gtk::Stack::new();
    stack.set_hexpand(true);
    stack.set_vexpand(true);
    let mut names: Vec<Option<String>> = Vec::new();

    add_settings_page(
        &sidebar,
        &stack,
        &mut names,
        "General",
        "preferences-system",
        general,
    );
    add_settings_page(
        &sidebar,
        &stack,
        &mut names,
        "Search",
        "system-search",
        search,
    );
    add_settings_page(
        &sidebar,
        &stack,
        &mut names,
        "Credentials",
        "dialog-password",
        credentials,
    );

    let section = gtk::ListBoxRow::new();
    section.set_selectable(false);
    section.set_activatable(false);
    let section_label = gtk::Label::new(Some("WIDGETS"));
    section_label.add_css_class("settings-section");
    section_label.set_halign(gtk::Align::Start);
    section.set_child(Some(&section_label));
    sidebar.append(&section);
    names.push(None);

    let widget_pages = vec![
        (
            "LiveBox",
            "utilities-system-monitor",
            livebox_page(&paths, &settings),
        ),
        ("NetBox", "network-wired", netbox_page(&paths, &settings)),
        (
            "DevBox",
            "utilities-terminal",
            devbox_page(&paths, &settings),
        ),
        (
            "Calendar",
            "x-office-calendar",
            calbox_page(&paths, &settings),
        ),
        ("Clipboard", "edit-paste", clipbox_page(&paths, &settings)),
        ("Battery", "battery-good", batbox_page(&paths, &settings)),
        (
            "Weather",
            "weather-few-clouds",
            weather_page(&paths, &settings),
        ),
        (
            "Clock",
            "preferences-system-time",
            clock_page(&paths, &settings),
        ),
        ("Git", "folder", git_page(&paths, &settings)),
        (
            "Market",
            "applications-internet",
            market_page(&paths, &settings),
        ),
        (
            "Open",
            "applications-development",
            open_page(&paths, &settings),
        ),
        ("Ship", "emblem-synchronizing", ship_page(&paths, &settings)),
        ("Tasks", "view-task", tasks_page(&paths, &settings)),
        ("Pull requests", "view-list", prs_page(&paths, &settings)),
        ("Logs", "text-x-generic", logbox_page(&paths, &settings)),
        (
            "Metrics",
            "view-statistics",
            metricbox_page(&paths, &settings),
        ),
    ];
    for (name, icon, page) in widget_pages {
        add_settings_page(&sidebar, &stack, &mut names, name, icon, page);
    }

    let stack_for_select = stack.clone();
    let names_for_select = names.clone();
    sidebar.connect_row_selected(move |_, row| {
        if let Some(row) = row {
            if let Some(Some(name)) = names_for_select.get(row.index() as usize) {
                stack_for_select.set_visible_child_name(name);
            }
        }
    });
    if let Some(row) = sidebar.row_at_index(0) {
        sidebar.select_row(Some(&row));
    }

    body.append(&sidebar);
    body.append(&stack);

    let header = gtk::Box::new(gtk::Orientation::Horizontal, 8);
    header.add_css_class("deck-header");
    header.set_margin_top(12);
    header.set_margin_bottom(8);
    header.set_margin_start(16);
    header.set_margin_end(16);
    let header_title = gtk::Label::new(Some("Deck Settings"));
    header_title.add_css_class("settings-title");
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
    root.append(&body);
    window.set_child(Some(&root));
    window
}

fn add_settings_page(
    sidebar: &gtk::ListBox,
    stack: &gtk::Stack,
    names: &mut Vec<Option<String>>,
    name: &str,
    icon: &str,
    page: gtk::Box,
) {
    let row = gtk::ListBoxRow::new();
    let line = gtk::Box::new(gtk::Orientation::Horizontal, 8);
    // Prefer monochrome symbolic icons, with fallbacks for names the Pi theme
    // does not ship.
    let base = match icon {
        "utilities-system-monitor" => "applications-system",
        "applications-internet" => "applications-utilities",
        "applications-development" => "applications-engineering",
        "emblem-synchronizing" => "view-refresh",
        "view-task" => "checkbox-checked",
        "view-statistics" => "x-office-spreadsheet",
        other => other,
    };
    let symbolic = format!("{base}-symbolic");
    let image = gtk::gdk::Display::default()
        .map(|display| {
            let theme = gtk::IconTheme::for_display(&display);
            if theme.has_icon(&symbolic) {
                gtk::Image::from_icon_name(&symbolic)
            } else {
                gtk::Image::from_icon_name(icon)
            }
        })
        .unwrap_or_else(|| gtk::Image::from_icon_name(icon));
    image.set_pixel_size(16);
    let label = gtk::Label::new(Some(name));
    label.set_halign(gtk::Align::Start);
    line.append(&image);
    line.append(&label);
    row.set_child(Some(&line));
    sidebar.append(&row);
    stack.add_named(&scrolled(page), Some(name));
    names.push(Some(name.to_string()));
}

fn calbox_page(paths: &Paths, settings: &Rc<RefCell<Settings>>) -> gtk::Box {
    let page = page();
    page.add_css_class("deck-page-cards");
    page.append(&caption(
        "CalDAV events for today and tomorrow. The password is stored with the CalDAV credential id.",
    ));
    let current = settings.borrow().calbox.clone();
    let general = form_card(&page, "GENERAL");
    size_row(&general, current.size, paths, settings, |s, v| {
        s.calbox.size = v
    });
    toggle(
        &general,
        "Show CalBox",
        current.enabled,
        paths,
        settings,
        |s, v| s.calbox.enabled = v,
    );
    text_field(
        &general,
        "CalDAV server URL",
        &current.server_url,
        "https://cal.example.com/dav/",
        paths,
        settings,
        |s, v| s.calbox.server_url = v,
    );
    text_field(
        &general,
        "Username",
        &current.username,
        "CalDAV username",
        paths,
        settings,
        |s, v| s.calbox.username = v,
    );
    let calendars = form_card(&page, "CALENDARS");
    calendar_picker(&calendars, paths, settings, &current);
    let display = form_card(&page, "DISPLAY");
    toggle(
        &display,
        "Show all-day events",
        current.show_all_day,
        paths,
        settings,
        |s, v| s.calbox.show_all_day = v,
    );
    toggle(
        &display,
        "Show today",
        current.show_today,
        paths,
        settings,
        |s, v| s.calbox.show_today = v,
    );
    toggle(
        &display,
        "Show tomorrow",
        current.show_tomorrow,
        paths,
        settings,
        |s, v| s.calbox.show_tomorrow = v,
    );
    spin(
        &display,
        "Today rows",
        current.today_count as u64,
        1,
        10,
        1,
        paths,
        settings,
        |s, v| s.calbox.today_count = v as u8,
    );
    spin(
        &display,
        "Tomorrow rows",
        current.tomorrow_count as u64,
        1,
        10,
        1,
        paths,
        settings,
        |s, v| s.calbox.tomorrow_count = v as u8,
    );
    toggle(
        &display,
        "Use calendar colors",
        current.use_calendar_colors,
        paths,
        settings,
        |s, v| s.calbox.use_calendar_colors = v,
    );
    color_row(
        &display,
        "Accent color",
        &current.accent_color,
        paths,
        settings,
        |s, v| s.calbox.accent_color = v,
    );
    page
}

fn batbox_page(paths: &Paths, settings: &Rc<RefCell<Settings>>) -> gtk::Box {
    let page = page();
    page.add_css_class("deck-page-cards");
    page.append(&caption(
        "Battery state from /sys/class/power_supply. Laptops and USB battery devices only; the Pi reports no battery.",
    ));
    let current = settings.borrow().batbox.clone();
    let general = form_card(&page, "GENERAL");
    size_row(&general, current.size, paths, settings, |s, v| {
        s.batbox.size = v
    });
    toggle(
        &general,
        "Show BatBox",
        current.enabled,
        paths,
        settings,
        |s, v| s.batbox.enabled = v,
    );
    toggle(
        &general,
        "Show battery",
        current.show_battery,
        paths,
        settings,
        |s, v| s.batbox.show_battery = v,
    );
    toggle(
        &general,
        "Show accessories",
        current.show_accessories,
        paths,
        settings,
        |s, v| s.batbox.show_accessories = v,
    );
    spin(
        &general,
        "Accessory rows",
        u64::from(current.accessory_count),
        1,
        10,
        1,
        paths,
        settings,
        |s, v| s.batbox.accessory_count = v as u8,
    );
    spin(
        &general,
        "Low battery percent",
        u64::from(current.low_percent),
        5,
        50,
        5,
        paths,
        settings,
        |s, v| s.batbox.low_percent = v as u8,
    );
    page
}

fn clipbox_page(paths: &Paths, settings: &Rc<RefCell<Settings>>) -> gtk::Box {
    let page = page();
    page.add_css_class("deck-page-cards");
    page.append(&caption(
        "Text clipboard history. Needs wl-clipboard on Wayland or xsel/xclip on X11.",
    ));
    let current = settings.borrow().clipbox.clone();
    let general = form_card(&page, "GENERAL");
    size_row(&general, current.size, paths, settings, |s, v| {
        s.clipbox.size = v
    });
    toggle(
        &general,
        "Show ClipBox",
        current.enabled,
        paths,
        settings,
        |s, v| s.clipbox.enabled = v,
    );
    toggle(
        &general,
        "Show list",
        current.show_list,
        paths,
        settings,
        |s, v| s.clipbox.show_list = v,
    );
    spin(
        &general,
        "History rows",
        current.history_count as u64,
        1,
        20,
        1,
        paths,
        settings,
        |s, v| s.clipbox.history_count = v as u8,
    );
    let colors = form_card(&page, "COLORS");
    color_row(
        &colors,
        "Text color",
        &current.text_color,
        paths,
        settings,
        |s, v| s.clipbox.text_color = v,
    );
    color_row(
        &colors,
        "Link/file color",
        &current.file_color,
        paths,
        settings,
        |s, v| s.clipbox.file_color = v,
    );
    page
}

fn calendar_picker(
    page: &gtk::Box,
    paths: &Paths,
    settings: &Rc<RefCell<Settings>>,
    current: &deck_core::settings::CalBoxSettings,
) {
    let row = gtk::Box::new(gtk::Orientation::Horizontal, 8);
    let load = gtk::Button::with_label("Load calendars");
    let status = caption("");
    row.append(&load);
    row.append(&status);
    page.append(&row);
    let list = gtk::Box::new(gtk::Orientation::Vertical, 2);
    page.append(&list);
    if !current.calendar_ids.is_empty() {
        status.set_text(&format!(
            "{} selected — load to edit",
            current.calendar_ids.len()
        ));
    } else {
        status.set_text("No selection = every VEVENT calendar");
    }
    let checks: Rc<RefCell<Vec<(String, gtk::CheckButton)>>> = Rc::new(RefCell::new(Vec::new()));
    let paths = paths.clone();
    let settings = settings.clone();
    let status_for_click = status.clone();
    load.connect_clicked(move |button| {
        let settings_snapshot = settings.borrow().calbox.clone();
        if settings_snapshot.server_url.trim().is_empty()
            || settings_snapshot.username.trim().is_empty()
        {
            status_for_click.set_text("Set the server URL and username first");
            return;
        }
        let Ok(password) = providers::require_token(&paths, "caldav") else {
            status_for_click.set_text("Store the CalDAV password in Credentials first");
            return;
        };
        button.set_sensitive(false);
        status_for_click.set_text("Loading…");
        let (tx, rx) = mpsc::channel();
        std::thread::spawn(move || {
            let _ = tx.send(deck_core::calbox::calendars(
                &settings_snapshot.server_url,
                &settings_snapshot.username,
                &password,
            ));
        });
        let list = list.clone();
        let checks = checks.clone();
        let settings = settings.clone();
        let paths = paths.clone();
        let status = status_for_click.clone();
        let button = button.clone();
        gtk::glib::timeout_add_local(Duration::from_millis(120), move || match rx.try_recv() {
            Ok(Ok(calendars)) => {
                widgets::clear(&list);
                checks.borrow_mut().clear();
                if calendars.is_empty() {
                    status.set_text("No VEVENT calendars found");
                    button.set_sensitive(true);
                    return gtk::glib::ControlFlow::Break;
                }
                for calendar in calendars {
                    let check = gtk::CheckButton::with_label(&calendar.title);
                    check.set_active(
                        settings.borrow().calbox.calendar_ids.is_empty()
                            || settings
                                .borrow()
                                .calbox
                                .calendar_ids
                                .iter()
                                .any(|id| id == &calendar.id),
                    );
                    let id = calendar.id.clone();
                    let checks_for_toggle = checks.clone();
                    let settings_for_toggle = settings.clone();
                    let paths_for_toggle = paths.clone();
                    check.connect_toggled(move |_| {
                        let selected: Vec<String> = checks_for_toggle
                            .borrow()
                            .iter()
                            .filter(|(_, check)| check.is_active())
                            .map(|(id, _)| id.clone())
                            .collect();
                        let all = checks_for_toggle.borrow().len();
                        let mut current = settings_for_toggle.borrow_mut();
                        current.calbox.calendar_ids = if selected.len() == all {
                            Vec::new()
                        } else {
                            selected
                        };
                        let _ = current.save(&paths_for_toggle);
                    });
                    checks.borrow_mut().push((id, check.clone()));
                    let line = gtk::Box::new(gtk::Orientation::Horizontal, 6);
                    line.append(&widgets::dot(&calendar.color));
                    line.append(&check);
                    list.append(&line);
                }
                status.set_text("Changes apply on the next deckd tick");
                button.set_sensitive(true);
                gtk::glib::ControlFlow::Break
            }
            Ok(Err(error)) => {
                status.set_text(&format!("Could not load: {}", error.message()));
                button.set_sensitive(true);
                gtk::glib::ControlFlow::Break
            }
            Err(mpsc::TryRecvError::Empty) => gtk::glib::ControlFlow::Continue,
            Err(mpsc::TryRecvError::Disconnected) => {
                status.set_text("Calendar discovery failed");
                button.set_sensitive(true);
                gtk::glib::ControlFlow::Break
            }
        });
    });
}

fn livebox_page(paths: &Paths, settings: &Rc<RefCell<Settings>>) -> gtk::Box {
    let page = page();
    page.append(&caption(
        "CPU, memory, disk and top processes. Size, visibility and colors apply on restart.",
    ));
    page.add_css_class("deck-page-cards");
    let current = settings.borrow().livebox.clone();

    let display = form_card(&page, "DISPLAY");
    size_row(&display, current.size, paths, settings, |s, v| {
        s.livebox.size = v
    });
    toggle(
        &display,
        "Show LiveBox",
        current.enabled,
        paths,
        settings,
        |s, v| s.livebox.enabled = v,
    );
    let metrics = form_card(&page, "METRICS");
    toggle(
        &metrics,
        "Show CPU",
        current.show_cpu,
        paths,
        settings,
        |s, v| s.livebox.show_cpu = v,
    );
    toggle(
        &metrics,
        "Show memory",
        current.show_mem,
        paths,
        settings,
        |s, v| s.livebox.show_mem = v,
    );
    toggle(
        &metrics,
        "Show disk",
        current.show_disk,
        paths,
        settings,
        |s, v| s.livebox.show_disk = v,
    );
    toggle(
        &metrics,
        "Show GPU",
        current.show_gpu,
        paths,
        settings,
        |s, v| s.livebox.show_gpu = v,
    );
    toggle(
        &metrics,
        "Show processes",
        current.show_processes,
        paths,
        settings,
        |s, v| s.livebox.show_processes = v,
    );
    let chart = form_card(&page, "CHART");
    toggle(
        &chart,
        "Show chart",
        current.show_chart,
        paths,
        settings,
        |s, v| s.livebox.show_chart = v,
    );
    toggle(
        &chart,
        "Per-core CPU lines",
        current.show_per_core_cores,
        paths,
        settings,
        |s, v| s.livebox.show_per_core_cores = v,
    );
    color_row(
        &chart,
        "CPU color",
        &current.cpu_color,
        paths,
        settings,
        |s, v| s.livebox.cpu_color = v,
    );
    color_row(
        &chart,
        "MEM color",
        &current.mem_color,
        paths,
        settings,
        |s, v| s.livebox.mem_color = v,
    );
    color_row(
        &chart,
        "DISK color",
        &current.disk_color,
        paths,
        settings,
        |s, v| s.livebox.disk_color = v,
    );
    color_row(
        &chart,
        "GPU color",
        &current.gpu_color,
        paths,
        settings,
        |s, v| s.livebox.gpu_color = v,
    );
    let processes = form_card(&page, "PROCESSES");
    spin(
        &processes,
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
        &processes,
        "Refresh (seconds)",
        current.refresh_seconds,
        5,
        120,
        5,
        paths,
        settings,
        |s, v| s.livebox.refresh_seconds = v,
    );
    let thresholds = form_card(&page, "THRESHOLDS");
    spin(
        &thresholds,
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
        &thresholds,
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
        &thresholds,
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
        &thresholds,
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
        &thresholds,
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
        &thresholds,
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
        &thresholds,
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
        &thresholds,
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
    page.add_css_class("deck-page-cards");
    let current = settings.borrow().netbox.clone();
    page.append(&caption(
        "Per-interface traffic from /proc/net/dev. Empty interface means every interface.",
    ));
    let card = form_card(&page, "SETTINGS");
    size_row(&card, current.size, paths, settings, |s, v| {
        s.netbox.size = v
    });
    toggle(
        &card,
        "Show NetBox",
        current.enabled,
        paths,
        settings,
        |s, v| s.netbox.enabled = v,
    );
    text_field(
        &card,
        "Interface (optional)",
        &current.interface,
        "e.g. eth0",
        paths,
        settings,
        |s, v| s.netbox.interface = v,
    );
    spin(
        &card,
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
        &card,
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
        &card,
        "Show packet rates",
        current.show_packets,
        paths,
        settings,
        |s, v| s.netbox.show_packets = v,
    );
    toggle(
        &card,
        "Show chart (large)",
        current.show_chart,
        paths,
        settings,
        |s, v| s.netbox.show_chart = v,
    );
    spin(
        &card,
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
        &card,
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
    page.add_css_class("deck-page-cards");
    let current = settings.borrow().devbox.clone();
    page.append(&caption(
        "Listening TCP ports from /proc and Docker containers from the docker CLI.",
    ));
    let card = form_card(&page, "SETTINGS");
    size_row(&card, current.size, paths, settings, |s, v| {
        s.devbox.size = v
    });
    toggle(
        &card,
        "Show DevBox",
        current.enabled,
        paths,
        settings,
        |s, v| s.devbox.enabled = v,
    );
    toggle(
        &card,
        "Show listening ports",
        current.show_ports,
        paths,
        settings,
        |s, v| s.devbox.show_ports = v,
    );
    toggle(
        &card,
        "Show containers",
        current.show_containers,
        paths,
        settings,
        |s, v| s.devbox.show_containers = v,
    );
    spin(
        &card,
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
        &card,
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
        &card,
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

fn weather_page(paths: &Paths, settings: &Rc<RefCell<Settings>>) -> gtk::Box {
    let page = page();
    page.add_css_class("deck-page-cards");
    let current = settings.borrow().weather.clone();
    page.append(&caption(
        "wttr.in current conditions and a three-day forecast. No account is needed.",
    ));
    let card = form_card(&page, "SETTINGS");
    size_row(&card, current.size, paths, settings, |s, v| {
        s.weather.size = v
    });
    toggle(
        &card,
        "Show WeatherBox",
        current.enabled,
        paths,
        settings,
        |s, v| s.weather.enabled = v,
    );
    text_field(
        &card,
        "Location (empty geolocates)",
        &current.location,
        "e.g. Amsterdam",
        paths,
        settings,
        |s, v| s.weather.location = v,
    );
    toggle(
        &card,
        "Fahrenheit",
        current.units_fahrenheit,
        paths,
        settings,
        |s, v| s.weather.units_fahrenheit = v,
    );
    toggle(
        &card,
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
    page.add_css_class("deck-page-cards");
    let current = settings.borrow().clock.clone();
    page.append(&caption(
        "IANA zone IDs, one per entry. `local` follows this machine.",
    ));
    let card = form_card(&page, "SETTINGS");
    size_row(&card, current.size, paths, settings, |s, v| {
        s.clock.size = v
    });
    toggle(
        &card,
        "Show ClockBox",
        current.enabled,
        paths,
        settings,
        |s, v| s.clock.enabled = v,
    );
    list_field(
        &card,
        "Cities",
        &current.city_ids,
        "local, Europe/Amsterdam, Asia/Tokyo",
        paths,
        settings,
        |s, v| s.clock.city_ids = v,
    );
    text_field(
        &card,
        "Main city (small face, optional)",
        &current.main_city_id,
        "empty = first non-local city",
        paths,
        settings,
        |s, v| s.clock.main_city_id = v,
    );
    toggle(
        &card,
        "Show relative day",
        current.show_relative_day,
        paths,
        settings,
        |s, v| s.clock.show_relative_day = v,
    );
    toggle(
        &card,
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
    page.add_css_class("deck-page-cards");
    let current = settings.borrow().git.clone();
    page.append(&caption(
        "Scans repo roots for .git directories and reads git log locally.",
    ));
    let card = form_card(&page, "SETTINGS");
    size_row(&card, current.size, paths, settings, |s, v| s.git.size = v);
    toggle(
        &card,
        "Show GitBox",
        current.enabled,
        paths,
        settings,
        |s, v| s.git.enabled = v,
    );
    list_field(
        &card,
        "Repo roots",
        &current.repo_paths,
        "~/dev, ~/work",
        paths,
        settings,
        |s, v| s.git.repo_paths = v,
    );
    spin(
        &card,
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
        &card,
        "Show chart",
        current.show_chart,
        paths,
        settings,
        |s, v| s.git.show_chart = v,
    );
    toggle(
        &card,
        "Show repos (large)",
        current.show_repos,
        paths,
        settings,
        |s, v| s.git.show_repos = v,
    );
    spin(
        &card,
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

fn coin_picker(
    page: &gtk::Box,
    paths: &Paths,
    settings: &Rc<RefCell<Settings>>,
    symbols_entry: gtk::Entry,
) {
    form_section(page, "LIVE PICKER");
    let row = gtk::Box::new(gtk::Orientation::Horizontal, 8);
    let query = gtk::Entry::new();
    query.set_placeholder_text(Some("Search coins or stocks, e.g. bitcoin or Apple"));
    query.set_hexpand(true);
    let search = gtk::Button::with_label("Search");
    row.append(&query);
    row.append(&search);
    page.append(&row);
    let status = caption("");
    page.append(&status);
    let results = gtk::Box::new(gtk::Orientation::Vertical, 2);
    page.append(&results);

    let busy = Rc::new(Cell::new(false));
    let paths = paths.clone();
    let settings = settings.clone();
    let status_for_click = status.clone();
    search.connect_clicked(move |button| {
        let text = query.text().trim().to_owned();
        if text.chars().count() < 2 {
            status_for_click.set_text("Type at least two characters");
            return;
        }
        if busy.get() {
            return;
        }
        busy.set(true);
        button.set_sensitive(false);
        let (tx, rx) = mpsc::channel();
        std::thread::spawn(move || {
            let mut hits = deck_core::market::search_coins(&text).unwrap_or_default();
            if let Ok(mut stocks) = deck_core::market::search_stocks(&text) {
                hits.append(&mut stocks);
            }
            let mut seen = std::collections::HashSet::new();
            hits.retain(|hit| seen.insert(hit.symbol.clone()));
            let _ = tx.send(hits);
        });
        let results = results.clone();
        let status = status_for_click.clone();
        let symbols_entry = symbols_entry.clone();
        let settings = settings.clone();
        let paths = paths.clone();
        let busy = busy.clone();
        let button = button.clone();
        gtk::glib::timeout_add_local(Duration::from_millis(120), move || match rx.try_recv() {
            Ok(hits) => {
                widgets::clear(&results);
                if hits.is_empty() {
                    status.set_text("No coins found");
                } else {
                    status.set_text("");
                }
                for hit in hits {
                    let rank = hit
                        .rank
                        .map(|rank| format!(" · #{rank}"))
                        .unwrap_or_default();
                    let label =
                        gtk::Button::with_label(&format!("{}  ·  {}{rank}", hit.symbol, hit.name));
                    label.add_css_class("link-row");
                    label.set_halign(gtk::Align::Start);
                    let entry = symbols_entry.clone();
                    let settings = settings.clone();
                    let paths = paths.clone();
                    let symbol = hit.symbol.clone();
                    label.connect_clicked(move |_| {
                        let current = entry.text().to_string();
                        let mut values: Vec<String> = current
                            .split(',')
                            .map(str::trim)
                            .filter(|value| !value.is_empty())
                            .map(str::to_owned)
                            .collect();
                        if !values
                            .iter()
                            .any(|value| value.eq_ignore_ascii_case(&symbol))
                        {
                            values.push(symbol.clone());
                        }
                        entry.set_text(&values.join(", "));
                        let mut current = settings.borrow_mut();
                        current.market.symbols = values;
                        let _ = current.save(&paths);
                    });
                    results.append(&label);
                }
                status.set_text("Pick a row to add its symbol");
                busy.set(false);
                button.set_sensitive(true);
                gtk::glib::ControlFlow::Break
            }
            Err(mpsc::TryRecvError::Empty) => gtk::glib::ControlFlow::Continue,
            Err(mpsc::TryRecvError::Disconnected) => {
                busy.set(false);
                button.set_sensitive(true);
                gtk::glib::ControlFlow::Break
            }
        });
    });
}

fn market_page(paths: &Paths, settings: &Rc<RefCell<Settings>>) -> gtk::Box {
    let page = page();
    page.add_css_class("deck-page-cards");
    let current = settings.borrow().market.clone();
    page.append(&caption(
        "Crypto, stocks, gold and fiat. Prices are converted to the display currency.",
    ));
    let card = form_card(&page, "SETTINGS");
    size_row(&card, current.size, paths, settings, |s, v| {
        s.market.size = v
    });
    toggle(
        &card,
        "Show MarketBox",
        current.enabled,
        paths,
        settings,
        |s, v| s.market.enabled = v,
    );
    let symbols_entry = list_field(
        &card,
        "Symbols",
        &current.symbols,
        "BTC, ETH, GOLD, AAPL, EUR",
        paths,
        settings,
        |s, v| s.market.symbols = v,
    );
    coin_picker(&card, paths, settings, symbols_entry);
    currency_row(&card, current.display_currency, paths, settings);
    spin(
        &card,
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
        &card,
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
    page.add_css_class("deck-page-cards");
    let current = settings.borrow().openbox.clone();
    page.append(&caption(
        "Reads the local opencode SQLite database by default; set a server URL to read `opencode serve` instead.",
    ));
    let card = form_card(&page, "SETTINGS");
    size_row(&card, current.size, paths, settings, |s, v| {
        s.openbox.size = v
    });
    toggle(
        &card,
        "Show OpenBox",
        current.enabled,
        paths,
        settings,
        |s, v| s.openbox.enabled = v,
    );
    account_row(
        &card,
        "opencode",
        "opencode account",
        "Default (server URL below)",
        &current.account_id,
        paths,
        settings,
        |s, v| s.openbox.account_id = v,
    );
    text_field(
        &card,
        "Server URL (optional)",
        &current.server_url,
        "http://127.0.0.1:4096 — empty = local database",
        paths,
        settings,
        |s, v| s.openbox.server_url = v,
    );
    toggle(
        &card,
        "Show models",
        current.show_models,
        paths,
        settings,
        |s, v| s.openbox.show_models = v,
    );
    toggle(
        &card,
        "Show tools",
        current.show_tools,
        paths,
        settings,
        |s, v| s.openbox.show_tools = v,
    );
    toggle(
        &card,
        "Show sessions (large)",
        current.show_sessions,
        paths,
        settings,
        |s, v| s.openbox.show_sessions = v,
    );
    spin(
        &card,
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
        &card,
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
        &card,
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
    page.add_css_class("deck-page-cards");
    let current = settings.borrow().ship.clone();
    page.append(&caption(
        "GitHub Actions runs for explicit repos. Add a GitHub token in Credentials.",
    ));
    let card = form_card(&page, "SETTINGS");
    size_row(&card, current.size, paths, settings, |s, v| s.ship.size = v);
    toggle(
        &card,
        "Show ShipBox",
        current.enabled,
        paths,
        settings,
        |s, v| s.ship.enabled = v,
    );
    account_row(
        &card,
        "github",
        "GitHub account",
        "Default (github token)",
        &current.github_account_id,
        paths,
        settings,
        |s, v| s.ship.github_account_id = v,
    );
    list_field(
        &card,
        "Repos",
        &current.repos,
        "owner/repo — empty discovers the 5 most recently pushed",
        paths,
        settings,
        |s, v| s.ship.repos = v,
    );
    spin(
        &card,
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
        &card,
        "Show runs",
        current.show_list,
        paths,
        settings,
        |s, v| s.ship.show_list = v,
    );
    page
}

#[allow(clippy::too_many_arguments)]
fn account_row(
    page: &gtk::Box,
    provider: &str,
    label: &str,
    default_label: &str,
    current: &str,
    paths: &Paths,
    settings: &Rc<RefCell<Settings>>,
    apply: fn(&mut Settings, String),
) {
    let row = gtk::Box::new(gtk::Orientation::Horizontal, 8);
    let title = gtk::Label::new(Some(label));
    title.set_halign(gtk::Align::Start);
    title.set_hexpand(true);
    let combo = gtk::ComboBoxText::new();
    combo.append(Some(""), default_label);
    for account in settings
        .borrow()
        .accounts
        .iter()
        .filter(|account| account.provider == provider)
    {
        let target = if !account.server_url.is_empty() {
            account.server_url.clone()
        } else if !account.organization.is_empty() || !account.project.is_empty() {
            format!("{}/{}", account.organization, account.project)
        } else {
            account.provider.clone()
        };
        combo.append(
            Some(&account.id),
            &format!("{} — {}", account.label, target.trim_matches('/')),
        );
    }
    combo.set_active_id(Some(current));
    let paths = paths.clone();
    let settings = settings.clone();
    combo.connect_changed(move |combo| {
        let mut current = settings.borrow_mut();
        apply(
            &mut current,
            combo.active_id().unwrap_or_default().to_string(),
        );
        let _ = current.save(&paths);
    });
    row.append(&title);
    row.append(&combo);
    page.append(&row);
}

fn tasks_page(paths: &Paths, settings: &Rc<RefCell<Settings>>) -> gtk::Box {
    let page = page();
    page.add_css_class("deck-page-cards");
    let current = settings.borrow().tasks.clone();
    page.append(&caption(
        "Azure DevOps work items assigned to you. Add an Azure PAT in Credentials.",
    ));
    let card = form_card(&page, "SETTINGS");
    size_row(&card, current.size, paths, settings, |s, v| {
        s.tasks.size = v
    });
    toggle(
        &card,
        "Show TaskBox",
        current.enabled,
        paths,
        settings,
        |s, v| s.tasks.enabled = v,
    );
    account_row(
        &card,
        "azure",
        "Azure account",
        "Default (Tasks fields)",
        &current.account_id,
        paths,
        settings,
        |s, v| s.tasks.account_id = v,
    );
    card.append(&caption(
        "A selected account uses its own organization and project; the fields below apply to Default.",
    ));
    text_field(
        &card,
        "Organization",
        &current.organization,
        "e.g. contoso",
        paths,
        settings,
        |s, v| s.tasks.organization = v,
    );
    text_field(
        &card,
        "Project",
        &current.project,
        "e.g. Manifold",
        paths,
        settings,
        |s, v| s.tasks.project = v,
    );
    text_field(
        &card,
        "WIQL (empty = assigned open items)",
        &current.query,
        "SELECT [System.Id] FROM WorkItems …",
        paths,
        settings,
        |s, v| s.tasks.query = v,
    );
    spin(
        &card,
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
        &card,
        "Show lane legend",
        current.show_legend,
        paths,
        settings,
        |s, v| s.tasks.show_legend = v,
    );
    toggle(
        &card,
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
    page.add_css_class("deck-page-cards");
    let current = settings.borrow().prs.clone();
    page.append(&caption(
        "GitHub and Azure DevOps review queues. Azure uses the Tasks organization and project.",
    ));
    let general = form_card(&page, "GENERAL");
    size_row(&general, current.size, paths, settings, |s, v| {
        s.prs.size = v
    });
    toggle(
        &general,
        "Show PRBox",
        current.enabled,
        paths,
        settings,
        |s, v| s.prs.enabled = v,
    );
    let providers = form_card(&page, "PROVIDERS");
    toggle(
        &providers,
        "GitHub",
        current.show_github,
        paths,
        settings,
        |s, v| s.prs.show_github = v,
    );
    account_row(
        &providers,
        "github",
        "GitHub account",
        "Default (github token)",
        &current.github_account_id,
        paths,
        settings,
        |s, v| s.prs.github_account_id = v,
    );
    toggle(
        &providers,
        "Azure DevOps",
        current.show_azure,
        paths,
        settings,
        |s, v| s.prs.show_azure = v,
    );
    account_row(
        &providers,
        "azure",
        "Azure account",
        "Default (Tasks fields)",
        &current.azure_account_id,
        paths,
        settings,
        |s, v| s.prs.azure_account_id = v,
    );
    providers.append(&caption(
        "A selected account uses its own organization and project.",
    ));
    let queue = form_card(&page, "QUEUE");
    toggle(
        &queue,
        "Review state",
        current.show_review_state,
        paths,
        settings,
        |s, v| s.prs.show_review_state = v,
    );
    spin(
        &queue,
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
        &queue,
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
    page.add_css_class("deck-page-cards");
    let current = settings.borrow().logbox.clone();
    page.append(&caption(
        "Elastic error/warn counts, 24h trend, services and recent lines. Add an Elastic API key in Credentials.",
    ));
    let card = form_card(&page, "SETTINGS");
    size_row(&card, current.size, paths, settings, |s, v| {
        s.logbox.size = v
    });
    toggle(
        &card,
        "Show LogBox",
        current.enabled,
        paths,
        settings,
        |s, v| s.logbox.enabled = v,
    );
    account_row(
        &card,
        "elastic",
        "Elastic account",
        "Default (base URL below)",
        &current.account_id,
        paths,
        settings,
        |s, v| s.logbox.account_id = v,
    );
    text_field(
        &card,
        "Elastic base URL",
        &current.base_url,
        "https://es.example.com",
        paths,
        settings,
        |s, v| s.logbox.base_url = v,
    );
    text_field(
        &card,
        "Environment",
        &current.environment,
        "prd, stg or logs-manifold-prd",
        paths,
        settings,
        |s, v| s.logbox.environment = v,
    );
    text_field(
        &card,
        "Service (optional)",
        &current.service,
        "empty = all services",
        paths,
        settings,
        |s, v| s.logbox.service = v,
    );
    text_mode_row(&card, current.text_mode, paths, settings);
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
        &card,
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
        &card,
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
        &card,
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
    page.add_css_class("deck-page-cards");
    let current = settings.borrow().metricbox.clone();
    page.append(&caption(
        "Grafana fleet, host, power, agents and alerts. Add a Grafana token in Credentials.",
    ));
    let card = form_card(&page, "SETTINGS");
    size_row(&card, current.size, paths, settings, |s, v| {
        s.metricbox.size = v
    });
    toggle(
        &card,
        "Show MetricBox",
        current.enabled,
        paths,
        settings,
        |s, v| s.metricbox.enabled = v,
    );
    account_row(
        &card,
        "grafana",
        "Grafana account",
        "Default (base URL below)",
        &current.account_id,
        paths,
        settings,
        |s, v| s.metricbox.account_id = v,
    );
    text_field(
        &card,
        "Grafana base URL",
        &current.base_url,
        "https://grafana.example.com",
        paths,
        settings,
        |s, v| s.metricbox.base_url = v,
    );
    metric_face_row(&card, current.face, paths, settings);
    text_field(
        &card,
        "Host (single-host face)",
        &current.host,
        "e.g. x201",
        paths,
        settings,
        |s, v| s.metricbox.host = v,
    );
    spin(
        &card,
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
        &card,
        "Show CPU",
        current.show_cpu,
        paths,
        settings,
        |s, v| s.metricbox.show_cpu = v,
    );
    toggle(
        &card,
        "Show RAM",
        current.show_ram,
        paths,
        settings,
        |s, v| s.metricbox.show_ram = v,
    );
    toggle(
        &card,
        "Show disk",
        current.show_disk,
        paths,
        settings,
        |s, v| s.metricbox.show_disk = v,
    );
    toggle(
        &card,
        "Show GPU",
        current.show_gpu,
        paths,
        settings,
        |s, v| s.metricbox.show_gpu = v,
    );
    toggle(
        &card,
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
    page.add_css_class("deck-page-cards");
    page.append(&caption(
        "Secret Service when available, otherwise a 0600 file. Tokens are read by deckd.",
    ));
    page.append(&caption(&format!(
        "Store: {} · fallback {}",
        deck_core::credentials::CredentialStore::detect(paths).kind(),
        paths.credentials_file().display()
    )));
    let card = form_card(&page, "TOKENS");
    credential_row(
        &card,
        paths,
        settings,
        "GitHub token",
        "github",
        VerifyKind::Github,
    );
    credential_row(
        &card,
        paths,
        settings,
        "Azure DevOps PAT",
        "azure",
        VerifyKind::Azure,
    );
    credential_row(
        &card,
        paths,
        settings,
        "Elastic API key",
        "elastic",
        VerifyKind::Elastic,
    );
    credential_row(
        &card,
        paths,
        settings,
        "Grafana token",
        "grafana",
        VerifyKind::Grafana,
    );
    credential_row(
        &card,
        paths,
        settings,
        "CalDAV password",
        "caldav",
        VerifyKind::CalDav,
    );
    credential_row(
        &card,
        paths,
        settings,
        "opencode serve token",
        "opencode",
        VerifyKind::Opencode,
    );
    opencode_row(&card);
    let accounts = form_card(&page, "ACCOUNTS");
    accounts_card(&accounts, paths, settings);
    page
}

fn accounts_card(page: &gtk::Box, paths: &Paths, settings: &Rc<RefCell<Settings>>) {
    let accounts = settings.borrow().accounts.clone();
    if accounts.is_empty() {
        page.append(&caption(
            "No named accounts. The provider tokens above remain the defaults.",
        ));
    }
    for account in accounts {
        let target = if account.server_url.is_empty() {
            format!("{}/{}", account.organization, account.project)
        } else {
            account.server_url.clone()
        };
        let title = gtk::Label::new(Some(&format!(
            "{} · {} — {}",
            account.label,
            account.provider,
            target.trim_matches('/')
        )));
        title.add_css_class("row-title");
        title.set_halign(gtk::Align::Start);
        page.append(&title);
        let row = gtk::Box::new(gtk::Orientation::Horizontal, 6);
        let entry = gtk::Entry::new();
        entry.set_visibility(false);
        entry.set_input_purpose(gtk::InputPurpose::Password);
        entry.set_placeholder_text(Some("stored token is not shown"));
        entry.set_hexpand(true);
        let save = gtk::Button::with_label("Save");
        let delete = gtk::Button::with_label("Delete");
        let verify = gtk::Button::with_label("Verify");
        let remove = gtk::Button::with_label("Remove");
        row.append(&entry);
        row.append(&save);
        row.append(&delete);
        row.append(&verify);
        row.append(&remove);
        page.append(&row);
        let status = caption("");
        page.append(&status);

        let id = account.id.clone();
        let paths_for_save = paths.clone();
        let status_for_save = status.clone();
        let entry_for_save = entry.clone();
        let id_for_save = id.clone();
        save.connect_clicked(move |_| {
            let value = entry_for_save.text().to_string();
            if value.trim().is_empty() {
                status_for_save.set_text("Enter a token first");
                return;
            }
            let store = deck_core::credentials::CredentialStore::detect(&paths_for_save);
            match store.write(&id_for_save, value.trim()) {
                Ok(()) => {
                    entry_for_save.set_text("");
                    status_for_save.set_text("Saved");
                }
                Err(error) => status_for_save.set_text(&format!("Could not save: {error}")),
            }
        });

        let paths_for_delete = paths.clone();
        let status_for_delete = status.clone();
        let id_for_delete = id.clone();
        delete.connect_clicked(move |_| {
            let store = deck_core::credentials::CredentialStore::detect(&paths_for_delete);
            match store.delete(&id_for_delete) {
                Ok(()) => status_for_delete.set_text("Deleted"),
                Err(error) => status_for_delete.set_text(&format!("Could not delete: {error}")),
            }
        });

        let paths_for_verify = paths.clone();
        let settings_for_verify = settings.clone();
        let status_for_verify = status.clone();
        let id_for_verify = id.clone();
        let provider = account.provider.clone();
        let organization = account.organization.clone();
        let server_url = account.server_url.clone();
        verify.connect_clicked(move |_| {
            let current = settings_for_verify.borrow();
            let base = if server_url.is_empty() {
                match provider.as_str() {
                    "elastic" => current.logbox.base_url.clone(),
                    "grafana" => current.metricbox.base_url.clone(),
                    "opencode" => current.openbox.server_url.clone(),
                    _ => String::new(),
                }
            } else {
                server_url.clone()
            };
            drop(current);
            let paths = paths_for_verify.clone();
            let id = id_for_verify.clone();
            let provider = provider.clone();
            let organization = organization.clone();
            verify_async(&status_for_verify, move || match provider.as_str() {
                "github" => verify_github_with(&paths, &id),
                "azure" => verify_azure_with(&paths, &organization, &id),
                "elastic" => verify_elastic_with(&paths, &base, &id),
                "grafana" => verify_grafana_with(&paths, &base, &id),
                "opencode" => verify_opencode_with(&paths, &base, &id),
                _ => "Unknown provider".into(),
            });
        });

        let paths_for_remove = paths.clone();
        let settings_for_remove = settings.clone();
        let status_for_remove = status.clone();
        let id_for_remove = id.clone();
        remove.connect_clicked(move |_| {
            {
                let mut current = settings_for_remove.borrow_mut();
                current
                    .accounts
                    .retain(|account| account.id != id_for_remove);
                let _ = current.save(&paths_for_remove);
            }
            let store = deck_core::credentials::CredentialStore::detect(&paths_for_remove);
            let _ = store.delete(&id_for_remove);
            status_for_remove.set_text("Removed — reopen Settings to refresh the list");
        });
    }

    widgets::section(page, "Add account");
    let fields = gtk::Box::new(gtk::Orientation::Vertical, 4);
    let provider = gtk::ComboBoxText::new();
    for (id, label) in [
        ("github", "GitHub"),
        ("azure", "Azure DevOps"),
        ("elastic", "Elastic"),
        ("grafana", "Grafana"),
        ("opencode", "opencode"),
    ] {
        provider.append(Some(id), label);
    }
    provider.set_active_id(Some("github"));
    let label = gtk::Entry::new();
    label.set_placeholder_text(Some("Label, e.g. Work"));
    let organization = gtk::Entry::new();
    organization.set_placeholder_text(Some("Organization (Azure)"));
    let project = gtk::Entry::new();
    project.set_placeholder_text(Some("Project (Azure)"));
    let server = gtk::Entry::new();
    server.set_placeholder_text(Some("Server / base URL (Elastic, Grafana, opencode)"));
    let token = gtk::Entry::new();
    token.set_visibility(false);
    token.set_input_purpose(gtk::InputPurpose::Password);
    token.set_placeholder_text(Some("Token or password"));
    fields.append(&provider);
    fields.append(&label);
    fields.append(&organization);
    fields.append(&project);
    fields.append(&server);
    fields.append(&token);
    page.append(&fields);
    let add = gtk::Button::with_label("Add account");
    add.set_halign(gtk::Align::Start);
    page.append(&add);
    let status = caption("");
    page.append(&status);
    let paths = paths.clone();
    let settings = settings.clone();
    add.connect_clicked(move |_| {
        let provider = provider
            .active_id()
            .map(|id| id.to_string())
            .unwrap_or_else(|| "github".into());
        let label_text = label.text().trim().to_owned();
        let token_text = token.text().trim().to_owned();
        if label_text.is_empty() || token_text.is_empty() {
            status.set_text("Fill in label and token");
            return;
        }
        let organization = organization.text().trim().to_owned();
        let project = project.text().trim().to_owned();
        let server_url = server.text().trim().trim_end_matches('/').to_owned();
        if provider == "azure" && (organization.is_empty() || project.is_empty()) {
            status.set_text("Azure accounts need organization and project");
            return;
        }
        if matches!(provider.as_str(), "elastic" | "grafana" | "opencode") && server_url.is_empty()
        {
            status.set_text("This provider needs a server or base URL");
            return;
        }
        let id = format!(
            "{provider}:{}",
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .map(|duration| duration.as_millis())
                .unwrap_or(0)
        );
        {
            let mut current = settings.borrow_mut();
            current
                .accounts
                .push(deck_core::settings::CredentialAccount {
                    id: id.clone(),
                    provider,
                    label: label_text,
                    organization,
                    project,
                    server_url,
                });
            let _ = current.save(&paths);
        }
        let store = deck_core::credentials::CredentialStore::detect(&paths);
        match store.write(&id, &token_text) {
            Ok(()) => status.set_text("Added — reopen Settings to manage the account"),
            Err(error) => status.set_text(&format!("Account saved, token failed: {error}")),
        }
    });
}

#[derive(Clone, Copy)]
enum VerifyKind {
    Github,
    Azure,
    Elastic,
    Grafana,
    Opencode,
    CalDav,
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
        let opencode_url = settings_for_verify.borrow().openbox.server_url.clone();
        let cal_url = settings_for_verify.borrow().calbox.server_url.clone();
        let cal_user = settings_for_verify.borrow().calbox.username.clone();
        verify_async(&status_for_verify, move || match kind {
            VerifyKind::Github => verify_github(&paths),
            VerifyKind::Azure => verify_azure(&paths, &org),
            VerifyKind::Elastic => verify_elastic(&paths, &log_base),
            VerifyKind::Grafana => verify_grafana(&paths, &metric_base),
            VerifyKind::Opencode => verify_opencode(&paths, &opencode_url),
            VerifyKind::CalDav => verify_caldav(&paths, &cal_url, &cal_user),
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

fn verify_caldav(paths: &Paths, server_url: &str, username: &str) -> String {
    if server_url.trim().is_empty() || username.trim().is_empty() {
        return "Set the CalDAV server URL and username first".into();
    }
    let Ok(password) = providers::require_token(paths, "caldav") else {
        return "No CalDAV password stored".into();
    };
    match deck_core::calbox::calendars(server_url, username, &password) {
        Ok(calendars) => format!("{} calendars found", calendars.len()),
        Err(error) => format!("CalDAV check failed: {}", error.message()),
    }
}

fn verify_opencode(paths: &Paths, server_url: &str) -> String {
    verify_opencode_with(paths, server_url, "opencode")
}

fn verify_opencode_with(paths: &Paths, server_url: &str, token_id: &str) -> String {
    if server_url.trim().is_empty() {
        return "Set the OpenBox server URL first".into();
    }
    let Ok(token) = providers::require_token(paths, token_id) else {
        return "No opencode token stored".into();
    };
    match deck_core::openbox::load_remote(server_url, &token) {
        Ok(snapshot) => format!(
            "{} sessions in the last 24h, {} total tokens",
            snapshot.sessions, snapshot.total_input
        ),
        Err(error) => format!("Remote opencode failed: {}", error.message()),
    }
}

fn verify_github(paths: &Paths) -> String {
    verify_github_with(paths, "github")
}

fn verify_github_with(paths: &Paths, token_id: &str) -> String {
    let Ok(token) = providers::require_token(paths, token_id) else {
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
    verify_azure_with(paths, organization, "azure")
}

fn verify_azure_with(paths: &Paths, organization: &str, token_id: &str) -> String {
    if organization.trim().is_empty() {
        return "Set the Tasks organization first".into();
    }
    let Ok(token) = providers::require_token(paths, token_id) else {
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
    verify_elastic_with(paths, base, "elastic")
}

fn verify_elastic_with(paths: &Paths, base: &str, token_id: &str) -> String {
    let Some(base) = providers::normalize_base(base) else {
        return "Set the LogBox base URL first".into();
    };
    let Ok(token) = providers::require_token(paths, token_id) else {
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
    verify_grafana_with(paths, base, "grafana")
}

fn verify_grafana_with(paths: &Paths, base: &str, token_id: &str) -> String {
    let Some(base) = providers::normalize_base(base) else {
        return "Set the MetricBox base URL first".into();
    };
    let Ok(token) = providers::require_token(paths, token_id) else {
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
) -> gtk::Entry {
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
    )
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

fn form_card(page: &gtk::Box, title: &str) -> gtk::Box {
    let label = gtk::Label::new(Some(title));
    label.add_css_class("form-section");
    label.set_halign(gtk::Align::Start);
    page.append(&label);
    let card = gtk::Box::new(gtk::Orientation::Vertical, 0);
    card.add_css_class("form-card");
    page.append(&card);
    card
}

fn form_section(page: &gtk::Box, title: &str) {
    let label = gtk::Label::new(Some(title));
    label.add_css_class("form-section");
    label.set_halign(gtk::Align::Start);
    page.append(&label);
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

fn color_row(
    page: &gtk::Box,
    label: &str,
    current: &str,
    paths: &Paths,
    settings: &Rc<RefCell<Settings>>,
    apply: fn(&mut Settings, String),
) {
    let row = gtk::Box::new(gtk::Orientation::Horizontal, 8);
    row.add_css_class("form-row");
    let title = gtk::Label::new(Some(label));
    title.set_halign(gtk::Align::Start);
    title.set_hexpand(true);
    let button = gtk::ColorButton::new();
    if let Ok(rgba) = gtk::gdk::RGBA::parse(current) {
        button.set_rgba(&rgba);
    }
    button.set_use_alpha(false);
    button.set_valign(gtk::Align::Center);
    let paths = paths.clone();
    let settings = settings.clone();
    button.connect_color_set(move |button| {
        let rgba = button.rgba();
        let hex = format!(
            "#{:02x}{:02x}{:02x}",
            (rgba.red() * 255.0).round() as u8,
            (rgba.green() * 255.0).round() as u8,
            (rgba.blue() * 255.0).round() as u8
        );
        let mut current = settings.borrow_mut();
        apply(&mut current, hex);
        let _ = current.save(&paths);
    });
    row.append(&title);
    row.append(&button);
    page.append(&row);
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
    let row = gtk::Box::new(gtk::Orientation::Horizontal, 8);
    row.add_css_class("form-row");
    let title = gtk::Label::new(Some(label));
    title.set_halign(gtk::Align::Start);
    title.set_hexpand(true);
    let switch = gtk::Switch::new();
    switch.set_active(active);
    switch.set_valign(gtk::Align::Center);
    let paths = paths.clone();
    let settings = settings.clone();
    switch.connect_active_notify(move |switch| {
        let mut current = settings.borrow_mut();
        apply(&mut current, switch.is_active());
        let _ = current.save(&paths);
        drop(current);
        refresh_widget_visibility(&settings);
    });
    row.append(&title);
    row.append(&switch);
    page.append(&row);
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
) -> gtk::Entry
where
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
    entry
}

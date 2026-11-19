use std::cell::RefCell;
use std::path::PathBuf;
use std::rc::Rc;

use deck_core::paths::Paths;
use deck_core::settings::Settings;
use gtk4 as gtk;
use gtk4::prelude::*;

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

pub fn widget_window(app: &gtk::Application) -> gtk::ApplicationWindow {
    let spec = deck_platform::surface::WidgetSpec::default();
    let window = deck_platform::surface::widget_window(app, &spec);
    window.add_css_class("deck-surface");

    let content = gtk::Box::new(gtk::Orientation::Vertical, 4);
    content.set_margin_top(16);
    content.set_margin_bottom(16);
    content.set_margin_start(20);
    content.set_margin_end(20);

    let title = gtk::Label::new(Some("Deck"));
    title.add_css_class("title");
    title.set_halign(gtk::Align::Start);
    let subtitle = gtk::Label::new(Some(&format!(
        "Linux L2 shell · {}",
        deck_platform::backend_name()
    )));
    subtitle.add_css_class("subtitle");
    subtitle.set_halign(gtk::Align::Start);
    content.append(&title);
    content.append(&subtitle);

    window.set_child(Some(&content));
    window
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
        .default_height(480)
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

    let widgets = page();
    widgets.append(&caption(
        "Widget settings arrive with the widget ports in L3-L5.",
    ));
    notebook.append_page(&widgets, Some(&tab("Widgets")));

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

fn page() -> gtk::Box {
    let page = gtk::Box::new(gtk::Orientation::Vertical, 10);
    page.add_css_class("deck-page");
    page.set_margin_top(16);
    page.set_margin_bottom(16);
    page.set_margin_start(16);
    page.set_margin_end(16);
    page
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

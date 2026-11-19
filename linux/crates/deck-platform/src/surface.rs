use std::sync::atomic::{AtomicU8, Ordering};

use deck_core::platform::{detect_session, SessionKind};
use deck_core::settings::SurfaceMode;
use gtk4 as gtk;
use gtk4::prelude::*;
use gtk4_layer_shell::{Edge, KeyboardMode, Layer, LayerShell};

use crate::x11;

/// A cross-DE widget surface. On layer-shell sessions it is a bottom-layer
/// surface; on X11 it is a desktop/below window; on GNOME Wayland it is the
/// documented dashboard fallback.
pub struct WidgetSpec {
    pub width: i32,
    pub height: i32,
    pub top: i32,
    pub left: i32,
    pub title: String,
}

impl Default for WidgetSpec {
    fn default() -> Self {
        Self {
            width: 360,
            height: 150,
            top: 80,
            left: 80,
            title: "Deck".into(),
        }
    }
}

static SURFACE_MODE: AtomicU8 = AtomicU8::new(0);

/// Set once at startup from settings; changing it requires a restart.
pub fn set_mode(mode: SurfaceMode) {
    let value = match mode {
        SurfaceMode::Auto => 0,
        SurfaceMode::LayerShell => 1,
        SurfaceMode::X11 => 2,
        SurfaceMode::Dashboard => 3,
    };
    SURFACE_MODE.store(value, Ordering::Relaxed);
}

pub fn mode() -> SurfaceMode {
    match SURFACE_MODE.load(Ordering::Relaxed) {
        1 => SurfaceMode::LayerShell,
        2 => SurfaceMode::X11,
        3 => SurfaceMode::Dashboard,
        _ => SurfaceMode::Auto,
    }
}

pub fn session() -> SessionKind {
    match mode() {
        SurfaceMode::Auto => detect_session(),
        SurfaceMode::LayerShell => SessionKind::LayerShell,
        SurfaceMode::X11 => SessionKind::X11,
        SurfaceMode::Dashboard => SessionKind::Dashboard,
    }
}

pub fn widget_window(app: &gtk::Application, spec: &WidgetSpec) -> gtk::ApplicationWindow {
    let window = gtk::ApplicationWindow::builder()
        .application(app)
        .title(&spec.title)
        .default_width(spec.width)
        .default_height(spec.height)
        .build();
    window.set_decorated(false);

    if uses_layer_shell() {
        window.init_layer_shell();
        window.set_layer(Layer::Bottom);
        window.set_anchor(Edge::Top, true);
        window.set_anchor(Edge::Left, true);
        window.set_margin(Edge::Top, spec.top);
        window.set_margin(Edge::Left, spec.left);
        window.set_namespace(Some("deck-widget"));
        window.set_keyboard_mode(KeyboardMode::None);
        window.set_exclusive_zone(0);
    } else if session() == SessionKind::X11 {
        window.set_can_focus(false);
        x11::mark_desktop_window(spec.title.clone());
    }
    window
}

/// The Spotlight-style panel: overlay layer on Wayland, a borderless normal
/// window on GNOME/X11.
pub fn overlay_window(app: &gtk::Application, width: i32, height: i32) -> gtk::ApplicationWindow {
    let window = gtk::ApplicationWindow::builder()
        .application(app)
        .title("Deck Search")
        .default_width(width)
        .default_height(height)
        .build();
    window.set_decorated(false);

    if uses_layer_shell() {
        window.init_layer_shell();
        window.set_layer(Layer::Overlay);
        window.set_anchor(Edge::Top, true);
        window.set_margin(Edge::Top, 100);
        window.set_namespace(Some("deck-search"));
        window.set_keyboard_mode(KeyboardMode::Exclusive);
    }
    window
}

/// Moves an already-created widget surface. Only layer-shell sessions are
/// placed here; X11 placement is the window manager's job.
pub fn place(window: &gtk::ApplicationWindow, x: i32, y: i32) {
    place_on(window, None, x, y);
}

pub fn place_on(
    window: &gtk::ApplicationWindow,
    monitor: Option<&gtk::gdk::Monitor>,
    x: i32,
    y: i32,
) {
    if uses_layer_shell() {
        if let Some(monitor) = monitor {
            window.set_monitor(Some(monitor));
        }
        window.set_margin(Edge::Top, y);
        window.set_margin(Edge::Left, x);
    }
}

pub fn uses_layer_shell() -> bool {
    session() == SessionKind::LayerShell && gtk4_layer_shell::is_supported()
}

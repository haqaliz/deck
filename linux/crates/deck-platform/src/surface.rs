use deck_core::platform::{detect_session, SessionKind};
use gtk4 as gtk;
use gtk4::prelude::*;
use gtk4_layer_shell::{Edge, KeyboardMode, Layer, LayerShell};

/// A cross-DE widget surface. On layer-shell sessions it is a bottom-layer
/// surface; elsewhere it is a plain window until the X11/dashboard backends
/// are completed in L7.
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
    }
    window
}

/// The Spotlight-style panel: overlay layer on Wayland, a borderless normal
/// window on GNOME/X11 until those backends get their own treatment.
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

pub fn uses_layer_shell() -> bool {
    detect_session() == SessionKind::LayerShell && gtk4_layer_shell::is_supported()
}

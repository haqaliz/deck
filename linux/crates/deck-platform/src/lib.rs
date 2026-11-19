//! Platform backends. L2 provides layer-shell/default surfaces; X11 and the
//! GNOME dashboard get their full treatment in L7.

pub mod surface;
mod x11;

pub use deck_core::platform::{detect_session, detect_session_from, SessionKind};

pub fn backend_name() -> &'static str {
    match surface::session() {
        SessionKind::LayerShell => "layer-shell",
        SessionKind::X11 => "x11",
        SessionKind::Dashboard => "dashboard",
        SessionKind::Unknown => "unknown",
    }
}

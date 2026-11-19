//! Platform backends arrive in L2. L1 owns only the session decision shared
//! by the daemon and the CLI.

pub use deck_core::platform::{detect_session, detect_session_from, SessionKind};

pub fn backend_name() -> &'static str {
    match detect_session() {
        SessionKind::LayerShell => "layer-shell",
        SessionKind::X11 => "x11",
        SessionKind::Dashboard => "dashboard",
        SessionKind::Unknown => "unknown",
    }
}

use std::env;
use std::path::Path;

/// Which widget surface backend the session needs.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SessionKind {
    /// Wayland with wlr-layer-shell (labwc, KDE, wlroots).
    LayerShell,
    /// X11 or GNOME-on-X11; desktop/below window types.
    X11,
    /// GNOME Wayland: no layer-shell, so a normal dashboard window.
    Dashboard,
    /// No display; daemon/CLI only.
    Unknown,
}

/// App id when running inside a Flatpak sandbox.
pub fn flatpak_id() -> Option<String> {
    std::env::var("FLATPAK_ID").ok().or_else(|| {
        Path::new("/.flatpak-info")
            .exists()
            .then(|| "io.github.haqaliz.deck".into())
    })
}

pub fn detect_session() -> SessionKind {
    let wayland = env::var_os("WAYLAND_DISPLAY").is_some();
    let x11 = env::var_os("DISPLAY").is_some();
    let desktop = env::var("XDG_CURRENT_DESKTOP").unwrap_or_default();
    detect_session_from(wayland, x11, &desktop)
}

/// Pure form so the matrix is testable without mutating process globals.
pub fn detect_session_from(wayland: bool, x11: bool, desktop: &str) -> SessionKind {
    if wayland {
        let desktop = desktop.to_ascii_lowercase();
        if desktop.contains("gnome") {
            SessionKind::Dashboard
        } else {
            SessionKind::LayerShell
        }
    } else if x11 {
        SessionKind::X11
    } else {
        SessionKind::Unknown
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn labwc_is_layer_shell() {
        assert_eq!(
            detect_session_from(true, true, "labwc:wlroots"),
            SessionKind::LayerShell
        );
    }

    #[test]
    fn kde_is_layer_shell() {
        assert_eq!(
            detect_session_from(true, false, "KDE"),
            SessionKind::LayerShell
        );
    }

    #[test]
    fn gnome_wayland_is_dashboard() {
        assert_eq!(
            detect_session_from(true, false, "GNOME"),
            SessionKind::Dashboard
        );
    }

    #[test]
    fn x11_is_x11() {
        assert_eq!(detect_session_from(false, true, "XFCE"), SessionKind::X11);
    }

    #[test]
    fn no_display_is_unknown() {
        assert_eq!(detect_session_from(false, false, ""), SessionKind::Unknown);
    }
}

import ServiceManagement

/// Deck.app's own login registration. Separate from `AgentService`, which owns
/// the two background agents: this one starts the app (and with it the tray
/// and the shortcut), those keep widget data fresh.
///
/// The status is the source of truth — never `settings.json` — because the
/// user can change it from System Settings → General → Login Items without
/// Deck running. Registration only works from an approved location, so a dev
/// build in `build.noindex` reports `.unavailable`/errors; verify through the
/// installed copy.
enum MainAppLoginItem {
    static var state: LoginItemState {
        LoginItemState(rawStatus: SMAppService.mainApp.status.rawValue)
    }

    /// Registers or unregisters, then returns the state the OS reports. A
    /// failure is returned as text; the caller shows it next to the toggle.
    @discardableResult
    static func set(_ enabled: Bool) -> (state: LoginItemState, error: String?) {
        let service = SMAppService.mainApp
        do {
            if enabled {
                if service.status != .enabled { try service.register() }
            } else {
                try service.unregister()
            }
            return (state, nil)
        } catch {
            return (state, error.localizedDescription)
        }
    }
}

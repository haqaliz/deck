import AppKit

/// The menu-bar item: Search, Settings, Quit.
///
/// An `NSStatusItem` owned by the app delegate rather than a SwiftUI
/// `MenuBarExtra`, because the hotkey and the panel are driven from AppKit and
/// the item has to exist (or visibly fail to) before the Dock icon is allowed
/// to go away — see `TrayLifecyclePolicy.activationPolicy`.
@MainActor
final class TrayController: NSObject {
    private var item: NSStatusItem?
    var onSearch: () -> Void = {}
    var onSettings: () -> Void = {}
    var onQuit: () -> Void = {}

    /// True once the status item actually exists with a button. Gates hiding
    /// the Dock icon: with no tray there would be no way back in.
    var isReady: Bool { item?.button != nil }

    func install() {
        guard item == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        guard let button = item.button else {
            NSStatusBar.system.removeStatusItem(item)
            return
        }
        button.image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: "Deck")
        button.image?.isTemplate = true

        let menu = NSMenu()
        menu.addItem(withTitle: "Search", action: #selector(search), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Settings…", action: #selector(settings), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Deck", action: #selector(quit), keyEquivalent: "q").target = self
        item.menu = menu
        self.item = item
    }

    @objc private func search() { onSearch() }
    @objc private func settings() { onSettings() }
    @objc private func quit() { onQuit() }
}

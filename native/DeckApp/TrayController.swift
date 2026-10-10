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
    private var searchItem: NSMenuItem?
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
        // The Deck "D" mark, cut from docs/deck.svg as a monochrome template so
        // macOS tints it for light and dark menu bars. 36px drawn at 18pt, so it
        // is sharp on Retina. If the resource is ever missing, say "Deck" rather
        // than leave an invisible status item with no way back in.
        if let url = Bundle.main.url(forResource: "MenuBarIcon", withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            image.size = NSSize(width: 18, height: 18)
            image.isTemplate = true
            image.accessibilityDescription = "Deck"
            button.image = image
        } else {
            button.title = "Deck"
        }

        let menu = NSMenu()
        let searchItem = menu.addItem(withTitle: "Search", action: #selector(search), keyEquivalent: "")
        searchItem.target = self
        self.searchItem = searchItem
        menu.addItem(withTitle: "Settings…", action: #selector(settings), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Deck", action: #selector(quit), keyEquivalent: "q").target = self
        item.menu = menu
        self.item = item
    }

    /// Shows the current global shortcut on the Search item, the way any Mac
    /// menu shows one. Called whenever the shortcut changes. A key with no menu
    /// equivalent shows no shortcut rather than a wrong one.
    ///
    /// Display only: the key equivalent also fires while this menu is open,
    /// which does the same thing the item does.
    func showSearchShortcut(keyCode: Int, modifiers: Int) {
        guard let searchItem else { return }
        guard let key = ShortcutFormat.menuKeyEquivalent(keyCode: keyCode) else {
            searchItem.keyEquivalent = ""
            searchItem.keyEquivalentModifierMask = []
            return
        }
        var mask: NSEvent.ModifierFlags = []
        if modifiers & 256 != 0 { mask.insert(.command) }
        if modifiers & 512 != 0 { mask.insert(.shift) }
        if modifiers & 2048 != 0 { mask.insert(.option) }
        if modifiers & 4096 != 0 { mask.insert(.control) }
        searchItem.keyEquivalent = key
        searchItem.keyEquivalentModifierMask = mask
    }

    @objc private func search() { onSearch() }
    @objc private func settings() { onSettings() }
    @objc private func quit() { onQuit() }
}

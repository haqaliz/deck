import AppKit
import SwiftUI

enum Corner: String, CaseIterable {
    case topLeft = "tl"
    case topRight = "tr"
    case bottomLeft = "bl"
    case bottomRight = "br"
}

@main
struct OpenBoxMain {
    @MainActor
    static func main() {
        let args = CommandLine.arguments
        var corner: Corner = .topLeft
        var margin: CGFloat = 20
        var clickThrough = false

        var i = 0
        while i < args.count {
            switch args[i] {
            case "--corner":
                i += 1
                if i < args.count, let parsed = Corner(rawValue: args[i]) {
                    corner = parsed
                }
            case "--margin":
                i += 1
                if i < args.count, let parsed = Double(args[i]) {
                    margin = CGFloat(parsed)
                }
            case "--click-through":
                clickThrough = true
            default:
                break
            }
            i += 1
        }

        let app = NSApplication.shared
        let delegate = AppDelegate(corner: corner, margin: margin, clickThrough: clickThrough)
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let corner: Corner
    private let margin: CGFloat
    private let clickThrough: Bool
    private let settingsStore = SettingsStore()
    private var widgetPanel: NSPanel?

    init(corner: Corner, margin: CGFloat, clickThrough: Bool) {
        self.corner = corner
        self.margin = margin
        self.clickThrough = clickThrough
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let contentView = ContentView(
            settings: settingsStore,
            onOpenSettings: {
                NSApp.activate(ignoringOtherApps: true)
            },
            onHeightChange: { [weak self] height in
                self?.setWidgetHeight(height)
            }
        )
        let hostingView = NSHostingView(rootView: contentView)
        let size = hostingView.fittingSize

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = hostingView
        panel.isFloatingPanel = true
        panel.level = .normal
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.animationBehavior = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.ignoresMouseEvents = clickThrough
        panel.isMovableByWindowBackground = !clickThrough

        position(panel, size: size)
        panel.orderFrontRegardless()

        self.widgetPanel = panel
    }

    /// Resizes the widget, anchored to its top edge.
    func setWidgetHeight(_ height: CGFloat) {
        guard let widget = widgetPanel else { return }
        guard abs(widget.frame.height - height) > 1 else { return }
        let topEdge = widget.frame.maxY
        var frame = widget.frame
        frame.size.height = height
        frame.origin.y = topEdge - height
        widget.setFrame(frame, display: true, animate: false)
    }

    private func position(_ panel: NSPanel, size: NSSize) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first {
            NSMouseInRect(mouse, $0.frame, false)
        } ?? NSScreen.main
        guard let screen else { return }
        let frame = screen.visibleFrame
        let x: CGFloat
        let y: CGFloat
        switch corner {
        case .topLeft:
            x = frame.minX + margin
            y = frame.maxY - size.height - margin
        case .topRight:
            x = frame.maxX - size.width - margin
            y = frame.maxY - size.height - margin
        case .bottomLeft:
            x = frame.minX + margin
            y = frame.minY + margin
        case .bottomRight:
            x = frame.maxX - size.width - margin
            y = frame.minY + margin
        }
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}

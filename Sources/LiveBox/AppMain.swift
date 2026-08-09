import AppKit
import SwiftUI

enum Corner: String, CaseIterable {
    case topLeft = "tl"
    case topRight = "tr"
    case bottomLeft = "bl"
    case bottomRight = "br"
}

@main
struct LiveBoxMain {
    @MainActor
    static func main() {
        let args = CommandLine.arguments
        var corner: Corner = .topRight
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
        if let i = args.firstIndex(of: "--debug-render"), i + 1 < args.count {
            renderDebugPNG(path: args[i + 1])
            exit(0)
        }
        let delegate = AppDelegate(corner: corner, margin: margin, clickThrough: clickThrough)
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

@MainActor
private func renderDebugPNG(path: String) {
    let store = SettingsStore()
    let view = ZStack(alignment: .topLeading) {
        VStack(alignment: .leading, spacing: 4) {
            SettingsView(settings: store)
        }
        .frame(width: 368, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.black.opacity(0.55))
        )
    }
    .frame(width: 368, height: 358)
    let renderer = ImageRenderer(content: view)
    renderer.scale = 1
    guard
        let img = renderer.nsImage,
        let tiff = img.tiffRepresentation,
        let rep = NSBitmapImageRep(data: tiff),
        let png = rep.representation(using: .png, properties: [:])
    else { return }
    try? png.write(to: URL(fileURLWithPath: path))
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
            onOpenSettings: { [weak self] in
                NSApp.activate(ignoringOtherApps: true)
                // Borderless panels don't become key on their own; without key
                // status SwiftUI text fields can't receive input.
                self?.widgetPanel?.makeKey()
            },
            onHeightChange: { [weak self] height in
                self?.setWidgetHeight(height)
            }
        )
        let hostingView = NSHostingView(rootView: contentView)
        hostingView.sizingOptions = .standardBounds
        let size = hostingView.fittingSize

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = hostingView
        hostingView.wantsLayer = true
        hostingView.layer?.cornerRadius = 22
        hostingView.layer?.masksToBounds = true
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
        DispatchQueue.main.async { [weak self] in
            guard let widget = self?.widgetPanel else { return }
            let topEdge = widget.frame.maxY
            var frame = widget.frame
            frame.size.height = height
            frame.origin.y = topEdge - height
            widget.setFrame(frame, display: true, animate: false)
        }
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

import SwiftUI
import Charts
import NetBoxCore

struct ContentView: View {
    @StateObject private var settings: SettingsStore
    @StateObject private var store: MetricsStore
    private let onOpenSettings: () -> Void
    private let onCloseSettings: () -> Void
    private let onHeightChange: (CGFloat) -> Void
    @State private var showSettings = CommandLine.arguments.contains("--debug-flip")
    @State private var frontHeight: CGFloat = 300
    @State private var panelHeight: CGFloat = 358

    init(
        settings: SettingsStore,
        onOpenSettings: @escaping () -> Void,
        onCloseSettings: @escaping () -> Void = {},
        onHeightChange: @escaping (CGFloat) -> Void
    ) {
        _settings = StateObject(wrappedValue: settings)
        _store = StateObject(wrappedValue: MetricsStore(settings: settings))
        self.onOpenSettings = onOpenSettings
        self.onCloseSettings = onCloseSettings
        self.onHeightChange = onHeightChange
    }

    init(
        settings: SettingsStore,
        store: MetricsStore,
        onOpenSettings: @escaping () -> Void,
        onCloseSettings: @escaping () -> Void = {},
        onHeightChange: @escaping (CGFloat) -> Void
    ) {
        _settings = StateObject(wrappedValue: settings)
        _store = StateObject(wrappedValue: store)
        self.onOpenSettings = onOpenSettings
        self.onCloseSettings = onCloseSettings
        self.onHeightChange = onHeightChange
    }

    private var settingsValue: NetBoxSettings { settings.settings }

    var body: some View {
        ZStack(alignment: .top) {
            frontFace
                .rotation3DEffect(
                    .degrees(showSettings ? -180 : 0),
                    axis: (x: 0, y: 1, z: 0),
                    perspective: 0.35
                )
                .opacity(showSettings ? 0 : 1)
                .allowsHitTesting(!showSettings)

            settingsFace
                .rotation3DEffect(
                    .degrees(showSettings ? 0 : 180),
                    axis: (x: 0, y: 1, z: 0),
                    perspective: 0.35
                )
                .opacity(showSettings ? 1 : 0)
                .allowsHitTesting(showSettings)
        }
        .frame(width: 368, height: panelHeight)
        .animation(.spring(response: 0.5, dampingFraction: 0.85), value: showSettings)
        .contextMenu {
            if !NativeWidgetDetector.isRegistered() {
                Button("Close", role: .destructive) {
                    NSApp.terminate(nil)
                }
            }
        }
        .onPreferenceChange(PanelHeightKey.self) { height in
            frontHeight = height
            if ProcessInfo.processInfo.environment["NETBOX_DEBUG"] != nil {
                print("NETBOX_DEBUG measured frontHeight=\(height)")
                fflush(stdout)
            }
            reportHeight()
        }
        .onChange(of: showSettings) { _ in
            reportHeight()
            if showSettings {
                onOpenSettings()
            } else {
                onCloseSettings()
            }
        }
        .onAppear {
            store.start()
            if showSettings { onOpenSettings() }
        }
        .onDisappear { store.stop() }
    }

    private func reportHeight() {
        let target = showSettings ? 358.0 : max(frontHeight, 200.0)
        panelHeight = target
        onHeightChange(target)
    }

    // MARK: - Front face (widget)

    private var frontFace: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if settingsValue.showChart {
                chart
            }
            if settingsValue.showInterfaces {
                Divider().overlay(.secondary.opacity(0.15))
                interfaceList
            }
        }
        .frame(width: 340)
        .padding(.top, 28)
        .padding(.horizontal, 14)
        .padding(.bottom, 14)
        .background(
            GeometryReader { geo in
                Color.clear.preference(key: PanelHeightKey.self, value: geo.size.height)
            }
        )
        .background(cardStyle)
    }

    private var header: some View {
        HStack(spacing: 14) {
            if settingsValue.showChart {
                RateLabel(title: "UP", value: store.header?.up ?? 0, color: settingsValue.upColor.color)
                RateLabel(title: "DOWN", value: store.header?.down ?? 0, color: settingsValue.downColor.color)
            }
            Spacer(minLength: 0)
            Button {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
                    showSettings = true
                }
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .font(.system(size: 12, weight: .semibold, design: .rounded))
        .monospacedDigit()
    }

    private var chart: some View {
        Chart(Array(store.history.enumerated()), id: \.offset) { index, sample in
            LineMark(
                x: .value("Time", index),
                y: .value("UP", sample.up),
                series: .value("Metric", "UP")
            )
            .foregroundStyle(settingsValue.upColor.color)
            .lineStyle(StrokeStyle(lineWidth: 1.5))
            .interpolationMethod(.catmullRom)

            LineMark(
                x: .value("Time", index),
                y: .value("DOWN", sample.down),
                series: .value("Metric", "DOWN")
            )
            .foregroundStyle(settingsValue.downColor.color)
            .lineStyle(StrokeStyle(lineWidth: 1.5))
            .interpolationMethod(.catmullRom)
        }
        .chartXAxis(.hidden)
        .chartYAxis {
            AxisMarks(position: .trailing, values: [0, store.peak / 2, store.peak]) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
                    .foregroundStyle(Color(white: 0.45).opacity(0.35))
                AxisValueLabel()
            }
        }
        .chartYScale(domain: 0...max(1, store.peak))
        .frame(height: 130)
        .animation(.linear(duration: 0.4), value: store.history.count)
    }

    private var interfaceList: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("INTERFACES")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .tracking(1)
                Spacer()
            }
            .padding(.bottom, 4)
            CustomScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(visibleInterfaces.enumerated()), id: \.offset) { _, iface in
                        HStack(spacing: 8) {
                            Text(iface.name)
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                            Spacer()
                            Text("↑ " + NetBoxFormatters.formatRate(iface.up))
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(settingsValue.upColor.color)
                            Text("↓ " + NetBoxFormatters.formatRate(iface.down))
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(settingsValue.downColor.color)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .frame(height: interfaceListHeight)
            .animation(.easeOut(duration: 0.2), value: interfaceListHeight)
        }
    }

    private var visibleInterfaces: [InterfaceRates] {
        let count = max(1, min(10, settingsValue.interfaceCount))
        return Array(store.interfaces.prefix(count))
    }

    /// Grows with the row count but never shows more than 6 rows (~140pt) at once.
    private var interfaceListHeight: CGFloat {
        let rows = CGFloat(max(1, visibleInterfaces.count))
        return min(rows * 23 + 6, 140)
    }

    // MARK: - Back face (settings)

    private var settingsFace: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("SETTINGS")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .tracking(1)
                Spacer()
                Button {
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
                        showSettings = false
                    }
                } label: {
                    Text("Done")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(.primary.opacity(0.12))
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 10)
            .padding(.top, 28)

            SettingsView(settings: settings)
        }
        .frame(width: 368, height: 358, alignment: .top)
        .background(cardStyle)
    }

    private var cardStyle: some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(.clear)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(.white.opacity(0.22), lineWidth: 0.5)
            )
    }
}

private struct PanelHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 300
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// Reaches into the backing NSScrollView to slim the native scrollbar
/// (thin overlay scroller with a light knob).
private struct ScrollViewStyler: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.setAccessibilityElement(false)
        DispatchQueue.main.async { [weak view] in
            guard let view, let scroll = view.enclosingScrollView else { return }
            scroll.scrollerStyle = .overlay
            scroll.scrollerKnobStyle = .light
            scroll.verticalScroller?.controlSize = .small
            scroll.horizontalScroller?.controlSize = .small
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

/// ScrollView wrapper with the native scrollbar stripped down.
private struct CustomScrollView<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            content.background(ScrollViewStyler())
        }
    }
}

private extension NSView {
    var enclosingScrollView: NSScrollView? {
        var current = superview
        while let view = current {
            if let scroll = view as? NSScrollView {
                return scroll
            }
            current = view.superview
        }
        return nil
    }
}

private struct RateLabel: View {
    let title: String
    let value: Double
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(title)
                .foregroundStyle(.secondary)
            Text(NetBoxFormatters.formatRate(value))
                .foregroundStyle(.primary)
        }
    }
}

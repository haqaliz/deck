import SwiftUI
import Charts

struct ContentView: View {
    @StateObject private var settings: SettingsStore
    @StateObject private var store: MetricsStore
    private let onOpenSettings: () -> Void
    private let onHeightChange: (CGFloat) -> Void
    @State private var processMode: ProcessMode = .cpu
    @State private var showSettings = CommandLine.arguments.contains("--debug-flip")
    @State private var frontHeight: CGFloat = 300

    init(
        settings: SettingsStore,
        onOpenSettings: @escaping () -> Void,
        onHeightChange: @escaping (CGFloat) -> Void
    ) {
        _settings = StateObject(wrappedValue: settings)
        _store = StateObject(wrappedValue: MetricsStore(settings: settings))
        self.onOpenSettings = onOpenSettings
        self.onHeightChange = onHeightChange
    }

    private var settingsValue: WidgetSettings { settings.settings }

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
        .animation(.spring(response: 0.5, dampingFraction: 0.85), value: showSettings)
        .contextMenu {
            Button("Close", role: .destructive) {
                NSApp.terminate(nil)
            }
        }
        .onPreferenceChange(PanelHeightKey.self) { height in
            frontHeight = height
            reportHeight()
        }
        .onChange(of: showSettings) { _ in
            reportHeight()
        }
        .onAppear { store.start() }
        .onDisappear { store.stop() }
    }

    private func reportHeight() {
        let target = showSettings ? 358.0 : max(frontHeight, 300.0)
        onHeightChange(target)
    }

    // MARK: - Front face (widget)

    private var frontFace: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if settingsValue.showChart {
                chart
            }
            if settingsValue.showProcesses {
                Divider().overlay(.secondary.opacity(0.15))
                processList
            }
        }
        .frame(width: 340, alignment: .top)
        .padding(14)
        .background(cardStyle)
        .background(
            GeometryReader { geo in
                Color.clear.preference(key: PanelHeightKey.self, value: geo.size.height)
            }
        )
    }

    private var header: some View {
        HStack(spacing: 14) {
            if settingsValue.showChart {
                if settingsValue.showCPU {
                    MetricLabel(title: "CPU", value: store.cpu, color: settingsValue.cpuColor.color)
                }
                if settingsValue.showMEM {
                    MetricLabel(title: "MEM", value: store.mem, color: settingsValue.memColor.color)
                }
                if settingsValue.showDisk {
                    MetricLabel(title: "DISK", value: store.disk, color: settingsValue.diskColor.color)
                }
            }
            Spacer(minLength: 0)
            Button {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
                    showSettings = true
                }
                onOpenSettings()
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
            if settingsValue.showCPU {
                LineMark(
                    x: .value("Time", index),
                    y: .value("CPU", sample.cpu),
                    series: .value("Metric", "CPU")
                )
                .foregroundStyle(settingsValue.cpuColor.color)
                .lineStyle(StrokeStyle(lineWidth: 1.5))
                .interpolationMethod(.catmullRom)
            }

            if settingsValue.showMEM {
                LineMark(
                    x: .value("Time", index),
                    y: .value("MEM", sample.mem),
                    series: .value("Metric", "MEM")
                )
                .foregroundStyle(settingsValue.memColor.color)
                .lineStyle(StrokeStyle(lineWidth: 1.5))
                .interpolationMethod(.catmullRom)
            }

            if settingsValue.showDisk {
                LineMark(
                    x: .value("Time", index),
                    y: .value("DISK", sample.disk),
                    series: .value("Metric", "DISK")
                )
                .foregroundStyle(settingsValue.diskColor.color)
                .lineStyle(StrokeStyle(lineWidth: 1.5))
                .interpolationMethod(.catmullRom)
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis {
            AxisMarks(position: .trailing, values: [0, 50, 100]) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
                    .foregroundStyle(Color(white: 0.45).opacity(0.35))
                AxisValueLabel()
                    .foregroundStyle(Color(white: 0.78))
                    .font(.system(size: 9, weight: .medium, design: .rounded))
            }
        }
        .chartYScale(domain: 0...100)
        .frame(height: 100)
        .animation(.linear(duration: 0.4), value: store.history.count)
    }

    private var processList: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("TOP PROCESSES")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .tracking(1)
                Spacer()
                ProcessTab(mode: $processMode)
            }
            .padding(.bottom, 4)
            CustomScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(currentProcesses.enumerated()), id: \.offset) { _, process in
                        HStack(spacing: 8) {
                            Text(process.name)
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                            Spacer()
                            Text(String(format: "%.1f%%", process.cpuPercent))
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(
                                    processMode == .cpu
                                        ? settingsValue.cpuColor.color
                                        : .secondary.opacity(0.8)
                                )
                            Text(String(format: "%.1f%%", process.memPercent))
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(
                                    processMode == .memory
                                        ? settingsValue.memColor.color
                                        : .secondary.opacity(0.8)
                                )
                        }
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .frame(height: processListHeight)
            .animation(.easeOut(duration: 0.2), value: processListHeight)
        }
    }

    private var currentProcesses: [TopProcess] {
        switch processMode {
        case .cpu: return store.processesByCPU
        case .memory: return store.processesByMemory
        }
    }

    /// Grows with the row count but never shows more than 5 rows (~110pt) at once.
    private var processListHeight: CGFloat {
        let rows = CGFloat(max(1, currentProcesses.count))
        return min(rows * 23 + 6, 110)
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
            .padding(.top, 14)

            SettingsView(settings: settings)
        }
        .frame(width: 368, height: 358, alignment: .top)
        .background(cardStyle)
    }

    private var cardStyle: some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(.white.opacity(0.12), lineWidth: 0.5)
            )
    }
}

private struct PanelHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 300
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

enum ProcessMode {
    case cpu
    case memory
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

private struct ProcessTab: View {
    @Binding var mode: ProcessMode

    var body: some View {
        HStack(spacing: 2) {
            tabButton("CPU", .cpu)
            tabButton("MEM", .memory)
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(.primary.opacity(0.08))
        )
    }

    private func tabButton(_ title: String, _ target: ProcessMode) -> some View {
        Button {
            withAnimation(.easeOut(duration: 0.15)) { mode = target }
        } label: {
            Text(title)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(mode == target ? Color.black : .secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(mode == target ? .white : .clear)
                )
        }
        .buttonStyle(.plain)
    }
}

private struct MetricLabel: View {
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
            Text(String(format: "%3.0f%%", value))
                .foregroundStyle(.primary)
        }
    }
}

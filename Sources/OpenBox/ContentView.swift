import OpenBoxCore
import SwiftUI
import Charts

struct ContentView: View {
    @StateObject private var settings: SettingsStore
    @StateObject private var store: MetricsStore
    private let onOpenSettings: () -> Void
    private let onHeightChange: (CGFloat) -> Void
    @State private var showSettings = CommandLine.arguments.contains("--debug-flip")
    @State private var frontHeight: CGFloat = 300
    @State private var panelHeight: CGFloat = 358

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

    private var settingsValue: OpenBoxSettings { settings.settings }

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
            if showSettings { onOpenSettings() }
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

    // MARK: - Front face

    private var frontFace: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if let metrics = store.metrics {
                if settingsValue.showChart && !metrics.daily.isEmpty {
                    chart(metrics)
                }
                if settingsValue.showModels && !metrics.models.isEmpty {
                    Divider().overlay(.secondary.opacity(0.15))
                    modelsList(metrics)
                }
                footer(metrics)
            } else if store.error != nil {
                errorView
            }
        }
        .frame(width: 340)
        .padding(.top, 32)
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
            if let metrics = store.metrics {
                MetricLabel(
                    title: "IN",
                    value: OpenCodeFormatters.formatTokens(metrics.todayInput),
                    color: settingsValue.inputColor.color
                )
                MetricLabel(
                    title: "OUT",
                    value: OpenCodeFormatters.formatTokens(metrics.todayOutput),
                    color: settingsValue.outputColor.color
                )
                MetricLabel(
                    title: "COST",
                    value: OpenCodeFormatters.formatCost(metrics.todayCost),
                    color: settingsValue.costColor.color
                )
            } else {
                Text("LOADING…")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
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

    private func chart(_ metrics: OpenCodeMetrics) -> some View {
        let maxValue = metrics.daily
            .map { max($0.input, $0.output) }
            .max() ?? 1
        return Chart(metrics.daily) { day in
            LineMark(
                x: .value("Day", OpenCodeFormatters.shortDay(day.day)),
                y: .value("Input", day.input),
                series: .value("Series", "Input")
            )
            .foregroundStyle(settingsValue.inputColor.color)
            .lineStyle(StrokeStyle(lineWidth: 1.5))
            .interpolationMethod(.catmullRom)

            LineMark(
                x: .value("Day", OpenCodeFormatters.shortDay(day.day)),
                y: .value("Output", day.output),
                series: .value("Series", "Output")
            )
            .foregroundStyle(settingsValue.outputColor.color)
            .lineStyle(StrokeStyle(lineWidth: 1.5))
            .interpolationMethod(.catmullRom)
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                AxisValueLabel()
                    .foregroundStyle(Color(white: 0.78))
                    .font(.system(size: 8, weight: .medium, design: .rounded))
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
                    .foregroundStyle(Color(white: 0.45).opacity(0.35))
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text(OpenCodeFormatters.formatTokens(Int64(v)))
                            .foregroundStyle(Color(white: 0.78))
                            .font(.system(size: 8, weight: .medium, design: .rounded))
                    }
                }
            }
        }
        .chartYScale(domain: 0...(Double(maxValue) * 1.15))
        .frame(height: 90)
    }

    private func modelsList(_ metrics: OpenCodeMetrics) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("MODELS")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
                .tracking(1)

            ForEach(metrics.models) { model in
                HStack(alignment: .center, spacing: 8) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(model.provider)
                            .font(.system(size: 9, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        HStack(spacing: 5) {
                            Text(model.modelID)
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                            if let variant = model.variant {
                                Text(variant)
                                    .font(.system(size: 9, weight: .bold, design: .rounded))
                                    .foregroundStyle(settingsValue.costColor.color)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(
                                        Capsule()
                                            .fill(settingsValue.costColor.color.opacity(0.15))
                                    )
                            }
                        }
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(OpenCodeFormatters.formatCost(model.cost))
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(settingsValue.costColor.color)
                        Text("\(OpenCodeFormatters.formatTokens(model.input)) / \(OpenCodeFormatters.formatTokens(model.output))")
                            .font(.system(size: 9, weight: .medium, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func footer(_ metrics: OpenCodeMetrics) -> some View {
        HStack {
            Text("\(store.isRemote ? "14D" : "All time"): \(OpenCodeFormatters.formatTokens(metrics.input)) in · \(OpenCodeFormatters.formatTokens(metrics.output)) out · \(OpenCodeFormatters.formatCost(metrics.cost))")
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer()
        }
        .padding(.top, 2)
    }

    private var errorView: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("NO METRICS")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
                .tracking(1)
            Text(store.error ?? "Could not read opencode metrics.")
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(.secondary)
        }
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
            .padding(.top, 32)

            CustomScrollView {
                SettingsView(settings: settings)
                    .padding(.bottom, 14)
            }
        }
        .frame(width: 368, height: 358, alignment: .top)
        .background(cardStyle)
    }

    private var cardStyle: some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(.white.opacity(0.22), lineWidth: 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

private struct PanelHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 300
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct MetricLabel: View {
    let title: String
    let value: String
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(title)
                .foregroundStyle(.secondary)
            Text(value)
                .foregroundStyle(.primary)
        }
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

import SwiftUI
import Charts
import GitBoxCore

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

    private var settingsValue: GitBoxSettings { settings.settings }

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
            if ProcessInfo.processInfo.environment["GITBOX_DEBUG"] != nil {
                print("GITBOX_DEBUG measured frontHeight=\(height)")
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
        .onChange(of: settings.settings) { _ in
            store.settingsDidChange()
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
            if store.isLoaded {
                if !store.hasRepos {
                    emptyState
                } else {
                    if settingsValue.showChart {
                        chart
                    }
                    if settingsValue.showRepos {
                        Divider().overlay(.secondary.opacity(0.15))
                        repoList
                    }
                }
            }
        }
        .frame(width: 340)
        .padding(.top, 36)
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
            MetricLabel(title: "TODAY", value: GitFormatters.commitCount(store.todayCount), color: settingsValue.todayColor.color)
            MetricLabel(title: "STREAK", value: GitFormatters.commitCount(store.streak), color: settingsValue.barColor.color)
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
        Chart(store.dayCounts, id: \.day) { item in
            BarMark(
                x: .value("Day", item.day),
                y: .value("Commits", item.count)
            )
            .foregroundStyle(
                item.day == todayLabel ? settingsValue.todayColor.color : settingsValue.barColor.color
            )
            .cornerRadius(2)
        }
        .chartXAxis(.hidden)
        .chartYAxis {
            AxisMarks(position: .trailing) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
                    .foregroundStyle(Color(white: 0.45).opacity(0.35))
                AxisValueLabel()
            }
        }
        .frame(height: 130)
        .animation(.linear(duration: 0.4), value: store.dayCounts)
    }

    private var repoList: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("REPOS")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .tracking(1)
                Spacer()
            }
            .padding(.bottom, 4)
            if visibleRepos.isEmpty {
                Text("No commits today")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            } else {
                CustomScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(visibleRepos.enumerated()), id: \.offset) { _, repo in
                            HStack(spacing: 8) {
                                Text(repo.name)
                                    .font(.system(size: 12, weight: .medium, design: .rounded))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                Spacer()
                                Text(GitFormatters.commitCount(repo.count))
                                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                                    .monospacedDigit()
                                    .foregroundStyle(settingsValue.todayColor.color)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .frame(height: repoListHeight)
                .animation(.easeOut(duration: 0.2), value: repoListHeight)
            }
        }
    }

    private var visibleRepos: [(name: String, count: Int)] {
        let count = max(1, min(10, settingsValue.repoCount))
        let active = Array(store.repos.prefix(count))
        let names = GitFormatters.disambiguatedNames(repos: active)
        return Array(zip(names, active.map(\.todayCount)))
    }

    /// Grows with the row count but never shows more than 6 rows (~140pt) at once.
    private var repoListHeight: CGFloat {
        let rows = CGFloat(max(1, visibleRepos.count))
        return min(rows * 23 + 6, 140)
    }

    private var todayLabel: String {
        GitMath.dayLabel(Date(), calendar: Calendar.current)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("No git repos found")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.primary)
            Text("Add paths in settings")
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
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

import SwiftUI
import BatBoxCore

struct ContentView: View {
    @StateObject private var settings: SettingsStore
    @StateObject private var store: MetricsStore
    private let onOpenSettings: () -> Void
    private let onCloseSettings: () -> Void
    private let onHeightChange: (CGFloat) -> Void
    @State private var showSettings = CommandLine.arguments.contains("--debug-flip")
    @State private var frontHeight: CGFloat = 200
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

    private var settingsValue: BatBoxSettings { settings.settings }

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
            if ProcessInfo.processInfo.environment["BATBOX_DEBUG"] != nil {
                print("BATBOX_DEBUG measured frontHeight=\(height)")
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
                LevelLabel(level: store.snapshot?.levelPercent)
                TimeLabel(snapshot: store.snapshot, color: settingsValue.levelColor.color)
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
    static var defaultValue: CGFloat = 200
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct LevelLabel: View {
    let level: Double?

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(tierColor)
                .frame(width: 7, height: 7)
            Text("LEVEL")
                .foregroundStyle(.secondary)
            Text(BatteryFormatters.formatPercent(level ?? 0))
                .foregroundStyle(.primary)
        }
    }

    private var tierColor: Color {
        guard let level else { return .gray }
        switch BatteryMath.tier(percent: level) {
        case .high: return .green
        case .medium: return .orange
        case .low: return .red
        }
    }
}

private struct TimeLabel: View {
    let snapshot: BatterySnapshot?
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text("TIME")
                .foregroundStyle(.secondary)
            Text(timeText)
                .foregroundStyle(.primary)
        }
    }

    private var timeText: String {
        guard let snapshot else { return "—" }
        if snapshot.isCharged { return "Full" }
        if snapshot.isCharging {
            return BatteryFormatters.formatTime(minutes: snapshot.timeToFullMinutes) + " to full"
        }
        return BatteryFormatters.formatTime(minutes: snapshot.timeToEmptyMinutes)
    }
}

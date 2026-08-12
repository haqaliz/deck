import WidgetKit
import SwiftUI

// MARK: - Timeline entry

struct DevBoxEntry: TimelineEntry {
    let date: Date
    let available: Bool
    let ports: [PortInfo]
    let containers: [ContainerInfo]
    let dockerState: DockerState
    let settings: DevBoxSettings
}

// MARK: - Provider

struct DevBoxProvider: TimelineProvider {
    func placeholder(in context: Context) -> DevBoxEntry {
        DevBoxEntry(
            date: .now,
            available: true,
            ports: [
                PortInfo(command: "opencode", host: "127.0.0.1", port: 4199),
                PortInfo(command: "postgres", host: "127.0.0.1", port: 5432),
                PortInfo(command: "redis-server", host: "127.0.0.1", port: 6379),
            ],
            containers: [
                ContainerInfo(name: "web", image: "nginx:latest", status: "Up 10 minutes", cpuPercent: 1.2, memPercent: 4.6),
            ],
            dockerState: .running,
            settings: DevBoxSettings()
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (DevBoxEntry) -> Void) {
        completion(makeEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DevBoxEntry>) -> Void) {
        let entry = makeEntry()
        let policy = TimelineReloadPolicy.after(Date().addingTimeInterval(60))
        completion(Timeline(entries: [entry], policy: policy))
    }

    private func makeEntry() -> DevBoxEntry {
        let snapshot = DevBoxSnapshotStore.load()
        let settings = DeckSettings.load().devbox
        guard let snapshot, snapshot.writtenAt.timeIntervalSinceNow > -300 else {
            return DevBoxEntry(
                date: .now,
                available: false,
                ports: [],
                containers: [],
                dockerState: .unavailable,
                settings: settings
            )
        }
        return DevBoxEntry(
            date: .now,
            available: true,
            ports: snapshot.ports,
            containers: snapshot.containers,
            dockerState: snapshot.dockerState,
            settings: settings
        )
    }
}

// MARK: - Widget

struct DevBoxWidget: Widget {
    let kind = "DevBoxWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: DevBoxProvider()) { entry in
            DevBoxWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("DevBox")
        .description("Open TCP listening ports and running Docker containers.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// MARK: - Views

struct DevBoxWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: DevBoxEntry

    var body: some View {
        Group {
            if !entry.available {
                unavailableView
            } else {
                switch family {
                case .systemSmall:
                    smallView
                case .systemMedium:
                    mediumView
                default:
                    largeView
                }
            }
        }
        .containerBackground(for: .widget) {
            Color.clear
        }
    }

    private var unavailableView: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("DevBox")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
            Text("No port data")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
            Text("Check Deck agent.")
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
    }

    private var smallView: some View {
        VStack(alignment: .leading, spacing: 8) {
            countRow(title: "PORTS", value: entry.ports.count, color: entry.settings.portColor.color)
            countRow(title: "CONTAINERS", value: entry.containers.count, color: entry.settings.containerColor.color)
        }
        .font(.system(size: 12, weight: .semibold, design: .rounded))
        .monospacedDigit()
    }

    private var mediumView: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 14) {
                countRow(title: "PORTS", value: entry.ports.count, color: entry.settings.portColor.color)
                countRow(title: "CONTAINERS", value: entry.containers.count, color: entry.settings.containerColor.color)
                Spacer()
            }
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .monospacedDigit()

            if entry.settings.showPorts {
                portsSection
            }
        }
    }

    private var largeView: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 14) {
                countRow(title: "PORTS", value: entry.ports.count, color: entry.settings.portColor.color)
                countRow(title: "CONTAINERS", value: entry.containers.count, color: entry.settings.containerColor.color)
                Spacer()
            }
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .monospacedDigit()

            if entry.settings.showPorts {
                portsSection
            }

            if entry.settings.showContainers {
                Divider()
                containersSection
            }

            Spacer(minLength: 0)
        }
    }

    private var portsSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("PORTS")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
                .tracking(1)
            if entry.ports.isEmpty {
                emptyLine("No listening ports")
            } else {
                ForEach(Array(entry.ports.prefix(entry.settings.portCount).enumerated()), id: \.offset) { _, port in
                    HStack(spacing: 6) {
                        Text(port.command)
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Spacer()
                        Text(Formatters.portLabel(host: port.host, port: port.port))
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(entry.settings.portColor.color)
                    }
                }
            }
        }
    }

    private var containersSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("CONTAINERS")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
                .tracking(1)
            switch entry.dockerState {
            case .unavailable:
                emptyLine("Docker unavailable")
            case .noContainers:
                emptyLine("No containers")
            case .running:
                if entry.containers.isEmpty {
                    emptyLine("No containers")
                } else {
                    ForEach(Array(entry.containers.prefix(entry.settings.containerCount).enumerated()), id: \.offset) { _, container in
                        HStack(spacing: 6) {
                            Circle()
                                .fill(statusColor(container.status))
                                .frame(width: 7, height: 7)
                            Text(container.name)
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                .lineLimit(1)
                                .truncationMode(.tail)
                            Spacer()
                            Text("\(Formatters.percentString(container.cpuPercent)) / \(Formatters.percentString(container.memPercent))")
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(entry.settings.containerColor.color)
                        }
                    }
                }
            }
        }
    }

    private func emptyLine(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .foregroundStyle(.secondary)
    }

    private func statusColor(_ status: String) -> Color {
        if status.hasPrefix("Up") { return .green }
        if status.hasPrefix("Paused") { return .gray }
        return .red
    }

    private func countRow(title: String, value: Int, color: Color) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(title)
                .foregroundStyle(.secondary)
            Text("\(value)")
                .foregroundStyle(.primary)
        }
    }
}

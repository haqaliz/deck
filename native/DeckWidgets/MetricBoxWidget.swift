import WidgetKit
import SwiftUI

// MARK: - Timeline entry

struct MetricBoxEntry: TimelineEntry {
    let date: Date
    let available: Bool
    let stale: Bool
    let writtenAt: Date?
    let chip: String?
    let snapshot: MetricBoxSnapshot?
    let settings: MetricBoxSettings
    /// Grafana's base. Empty when no Grafana account is picked.
    let baseURL: String
}

// MARK: - Provider

struct MetricBoxProvider: TimelineProvider {
    func placeholder(in context: Context) -> MetricBoxEntry {
        let names = ["x201", "x202", "x203", "x204", "x205", "x300", "x301"]
        var hosts: [MetricHost] = []
        for (index, name) in names.enumerated() {
            hosts.append(MetricHost(
                host: name,
                cpu: Double(12 + index * 11),
                ram: Double(38 + index * 5),
                disk: Double(51 + index * 3),
                lastSeenSeconds: 4,
                uptimeSeconds: 864_000,
                gpuPercent: index == 0 ? 62 : nil,
                kwh24h: 2.1
            ))
        }
        return MetricBoxEntry(
            date: .now, available: true, stale: false, writtenAt: .now, chip: nil,
            snapshot: MetricBoxSnapshot(
                accountID: "preview",
                hosts: hosts, agents: [], firingAlerts: [],
                trendHost: nil, trendCPU: [], writtenAt: .now, note: nil
            ),
            settings: MetricBoxSettings(), baseURL: "https://grafana.example"
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (MetricBoxEntry) -> Void) {
        completion(makeEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<MetricBoxEntry>) -> Void) {
        let entry = makeEntry()
        completion(Timeline(
            entries: [entry],
            policy: .after(Date().addingTimeInterval(60))
        ))
    }

    private func makeEntry() -> MetricBoxEntry {
        let settings = DeckSettings.load()
        let metricbox = settings.metricbox
        let account = settings.account(for: .metricboxGrafana)
        let stored = account == nil ? nil : MetricBoxSnapshotStore.load()
        // A snapshot belongs to one account. Showing it under another is worse
        // than showing nothing until the next fetch.
        let snapshot = stored.flatMap { candidate -> MetricBoxSnapshot? in
            guard candidate.accountID == account?.id else { return nil }
            return candidate
        }
        let now = Date()
        let chip = FetchChip.text(
            source: .metricbox,
            status: FetchStatusStore.load(.metricbox),
            dataWrittenAt: snapshot?.writtenAt,
            now: now
        )

        return MetricBoxEntry(
            date: now,
            available: snapshot != nil,
            stale: snapshot.map { now.timeIntervalSince($0.writtenAt) > 5 * 60 } ?? false,
            writtenAt: snapshot?.writtenAt,
            chip: chip,
            snapshot: snapshot,
            settings: metricbox,
            baseURL: account?.baseURL ?? ""
        )
    }
}

// MARK: - Widget

struct MetricBoxWidget: Widget {
    let kind = "MetricBoxWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: MetricBoxProvider()) { entry in
            MetricBoxWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("MetricBox")
        .description("Machine CPU, memory, disk and power from Grafana.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// MARK: - Views

struct MetricBoxWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: MetricBoxEntry

    var body: some View {
        Group {
            if entry.available, let snapshot = entry.snapshot {
                switch entry.settings.face {
                case .fleetHealth: fleetView(snapshot)
                case .singleHost: singleHostView(snapshot)
                case .power: powerView(snapshot)
                case .topAgents: agentsView(snapshot)
                case .alerts: alertsView(snapshot)
                }
            } else {
                unavailableView
            }
        }
        .containerBackground(for: .widget) { Color.clear }
        .widgetURL(family == .systemSmall ? link : nil)
    }

    private var unavailableView: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("MetricBox")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
            Text("No machine data")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
            Text(entry.chip ?? "Pick a Grafana account in Deck settings.")
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
    }

    // MARK: Fleet

    @ViewBuilder
    private func fleetView(_ snapshot: MetricBoxSnapshot) -> some View {
        let hosts = MetricBoxSort.worstFirst(snapshot.hosts, hidden: entry.settings.hiddenHosts)
        if family == .systemSmall {
            VStack(alignment: .leading, spacing: 5) {
                header("FLEET")
                ForEach(hosts.prefix(3)) { host in
                    compactHostRow(host)
                }
                Spacer(minLength: 0)
            }
        } else {
            VStack(alignment: .leading, spacing: 5) {
                header("FLEET · \(hosts.count) HOSTS")
                ForEach(hosts) { host in
                    hostRow(host, detailed: family == .systemLarge)
                }
                Spacer(minLength: 0)
                footer(snapshot)
            }
        }
    }

    private func compactHostRow(_ host: MetricHost) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(host.host)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .frame(width: 34, alignment: .leading)
            if isSilent(host) {
                Text("silent \(age(host.lastSeenSeconds))")
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundStyle(.red)
                Spacer(minLength: 0)
            } else {
                if entry.settings.showCPU {
                    Text("C \(percent(host.cpu))")
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(pressureColor(host.cpu))
                }
                if entry.settings.showCPU && entry.settings.showRAM {
                    Spacer(minLength: 2)
                }
                if entry.settings.showRAM {
                    Text("M \(percent(host.ram))")
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                if !entry.settings.showCPU && !entry.settings.showRAM {
                    Text(entry.settings.showDisk ? "D \(percent(host.disk))" : "\u{2014}")
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(entry.settings.showDisk ? pressureColor(host.disk) : Color.secondary)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func hostRow(_ host: MetricHost, detailed: Bool) -> some View {
        HStack(alignment: .center, spacing: 6) {
            Text(host.host)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .frame(width: 34, alignment: .leading)
            if isSilent(host) {
                Text("silent \(age(host.lastSeenSeconds))")
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundStyle(.red)
                Spacer(minLength: 0)
            } else {
                if entry.settings.showCPU { metric("C", host.cpu) }
                if entry.settings.showRAM { metric("M", host.ram) }
                if entry.settings.showDisk { metric("D", host.disk) }
                if detailed {
                    if entry.settings.showGPU {
                        if let gpu = host.gpuPercent {
                            metric("G", gpu)
                        } else {
                            Text("G —")
                                .font(.system(size: 9, weight: .medium, design: .rounded))
                                .foregroundStyle(.tertiary)
                                .frame(width: 40, alignment: .leading)
                        }
                    }
                    if entry.settings.showPower, let watts = host.totalWatts {
                        Text(wattsString(watts))
                            .font(.system(size: 9, weight: .medium, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 42, alignment: .trailing)
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func metric(_ label: String, _ value: Double?) -> some View {
        HStack(spacing: 3) {
            Text(label)
                .font(.system(size: 8, weight: .bold, design: .rounded))
                .foregroundStyle(.tertiary)
            MiniBar(value: value ?? 0, color: pressureColor(value))
                .frame(width: 22, height: 3)
            Text(percent(value))
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(pressureColor(value))
                .frame(width: 28, alignment: .leading)
        }
    }

    // MARK: Single host

    @ViewBuilder
    private func singleHostView(_ snapshot: MetricBoxSnapshot) -> some View {
        let host = chosenHost(snapshot)
        if let host {
            VStack(alignment: .leading, spacing: 5) {
                header("HOST · \(host.host)")
                if family == .systemSmall {
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text(percent(host.cpu))
                            .font(.system(size: 27, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                        Text("CPU")
                            .font(.system(size: 9, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("M \(percent(host.ram))")
                            .font(.system(size: 9, weight: .medium, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    Text("D \(percent(host.disk)) · up \(uptime(host.uptimeSeconds))")
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                } else {
                    HStack(alignment: .top, spacing: 12) {
                        bigStat("CPU", host.cpu)
                        bigStat("RAM", host.ram)
                        bigStat("DISK", host.disk)
                        if family == .systemLarge {
                            bigStat("GPU", host.gpuPercent)
                            bigStat("VRAM", host.vramPercent)
                        }
                        Spacer(minLength: 0)
                    }
                    if family == .systemLarge, let gpuTemp = host.gpuTemperature {
                        Text("GPU \(Int(gpuTemp))°C · up \(uptime(host.uptimeSeconds)) · \(age(host.lastSeenSeconds)) ago")
                            .font(.system(size: 9, weight: .medium, design: .rounded))
                            .foregroundStyle(.tertiary)
                    }
                    if snapshot.trendHost == host.host, !snapshot.trendCPU.isEmpty {
                        MetricTrendBars(values: snapshot.trendCPU, color: entry.settings.accentColor.color)
                            .frame(height: 22)
                    }
                }
                Spacer(minLength: 0)
                footer(snapshot)
            }
        } else {
            unavailableView
        }
    }

    private func bigStat(_ label: String, _ value: Double?) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(percent(value))
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(pressureColor(value))
            Text(label)
                .font(.system(size: 8, weight: .bold, design: .rounded))
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: Power

    @ViewBuilder
    private func powerView(_ snapshot: MetricBoxSnapshot) -> some View {
        let hosts = MetricBoxSort.worstFirst(snapshot.hosts, hidden: entry.settings.hiddenHosts)
        let watts = hosts.compactMap(\.totalWatts).reduce(0, +)
        let kwh = hosts.compactMap(\.kwh24h).reduce(0, +)
        let cost = MetricBoxSort.monthlyCost(
            kwh24h: kwh, ratePerKWh: entry.settings.ratePerKWh
        )
        VStack(alignment: .leading, spacing: 6) {
            header("POWER")
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(wattsString(watts))
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text("now")
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 4)
                Text("\(kwhString(kwh)) · \(costString(cost)) / mo")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            if family != .systemSmall {
                Divider()
                ForEach(hosts.filter { $0.totalWatts != nil }, id: \.host) { host in
                    HStack(spacing: 6) {
                        Text(host.host)
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .frame(width: 34, alignment: .leading)
                        Text(wattsString(host.totalWatts ?? 0))
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .monospacedDigit()
                        Spacer(minLength: 0)
                        Text(kwhString(host.kwh24h ?? 0))
                            .font(.system(size: 9, weight: .medium, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: Agents

    @ViewBuilder
    private func agentsView(_ snapshot: MetricBoxSnapshot) -> some View {
        let agents = Array(snapshot.agents.prefix(family == .systemSmall ? 3 : (family == .systemMedium ? 6 : 10)))
        VStack(alignment: .leading, spacing: 5) {
            header("TOP AGENTS")
            if agents.isEmpty {
                Text("No agent metrics")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(agents) { agent in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(agent.name)
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 4)
                        if let vram = agent.vram {
                            Text(vramString(vram))
                                .font(.system(size: 9, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(entry.settings.accentColor.color)
                        }
                        if let gpu = agent.gpu {
                            Text("G \(Int(gpu))%")
                                .font(.system(size: 9, weight: .medium, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        if let cpu = agent.cpu {
                            Text("C \(Int(cpu))%")
                                .font(.system(size: 9, weight: .medium, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: Alerts

    @ViewBuilder
    private func alertsView(_ snapshot: MetricBoxSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            header("ALERTS")
            if snapshot.firingAlerts.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(entry.settings.accentColor.color)
                    Text("No firing alerts")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                }
                Text("Grafana alerting · checked every minute")
                    .font(.system(size: 9, design: .rounded))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(snapshot.firingAlerts.prefix(family == .systemSmall ? 2 : 5)) { alert in
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Circle()
                            .fill(alert.severity == "critical" ? Color.red : Color.orange)
                            .frame(width: 5, height: 5)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(alert.name)
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                                .lineLimit(1)
                            if !alert.host.isEmpty {
                                Text(alert.host)
                                    .font(.system(size: 9, design: .rounded))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: Shared pieces

    private func header(_ title: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text("METRICBOX")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(entry.settings.accentColor.color.opacity(0.16), in: Capsule())
                .foregroundStyle(entry.settings.accentColor.color)
                .lineLimit(1)
            Spacer(minLength: 2)
            if let chip = entry.chip {
                Text(chip)
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            } else if entry.stale, let writtenAt = entry.writtenAt {
                Text(timeString(writtenAt))
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
            }
        }
    }

    @ViewBuilder
    private func footer(_ snapshot: MetricBoxSnapshot) -> some View {
        if let note = snapshot.note {
            HStack(spacing: 4) {
                Text(note)
                    .font(.system(size: 9, design: .rounded))
                    .foregroundStyle(.tertiary)
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: Links and formatting

    private var link: URL? {
        switch entry.settings.face {
        case .power:
            return InfraLinks.grafanaDashboard(
                baseURL: entry.baseURL, uid: "power", host: nil,
                fromMinutes: entry.settings.largeWindowMinutes
            )
        case .topAgents:
            return InfraLinks.grafanaDashboard(
                baseURL: entry.baseURL, uid: "top-agents", host: nil,
                fromMinutes: entry.settings.largeWindowMinutes
            )
        case .alerts:
            return InfraLinks.grafanaAlerts(baseURL: entry.baseURL)
        case .singleHost:
            return InfraLinks.grafanaDashboard(
                baseURL: entry.baseURL, uid: "fleet-overview",
                host: chosenHost(entry.snapshot)?.host,
                fromMinutes: entry.settings.largeWindowMinutes
            )
        case .fleetHealth:
            return InfraLinks.grafanaDashboard(
                baseURL: entry.baseURL, uid: "fleet-overview", host: nil,
                fromMinutes: entry.settings.largeWindowMinutes
            )
        }
    }

    private func chosenHost(_ snapshot: MetricBoxSnapshot?) -> MetricHost? {
        guard let snapshot else { return nil }
        let visible = MetricBoxSort.worstFirst(
            snapshot.hosts, hidden: entry.settings.hiddenHosts
        )
        if let picked = visible.first(where: { $0.host == entry.settings.host }) {
            return picked
        }
        return visible.first
    }

    private func isSilent(_ host: MetricHost) -> Bool {
        (host.lastSeenSeconds ?? 0) > MetricBoxSort.silentAfter
    }

    private func pressureColor(_ value: Double?) -> Color {
        guard let value else { return .secondary }
        if value >= 90 { return .red }
        if value >= 70 { return .orange }
        return entry.settings.accentColor.color
    }

    private func percent(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "—" }
        return "\(Int(value.rounded()))%"
    }

    private func age(_ seconds: Double?) -> String {
        guard let seconds, seconds.isFinite else { return "—" }
        if seconds < 60 { return "\(Int(seconds))s" }
        if seconds < 3600 { return "\(Int(seconds / 60))m" }
        if seconds < 86_400 { return "\(Int(seconds / 3600))h" }
        return "\(Int(seconds / 86_400))d"
    }

    private func uptime(_ seconds: Double?) -> String {
        guard let seconds, seconds.isFinite else { return "—" }
        let days = Int(seconds / 86_400)
        if days >= 1 { return "\(days)d" }
        return "\(Int(seconds / 3600))h"
    }

    private func wattsString(_ watts: Double) -> String {
        if watts >= 1000 { return String(format: "%.1fk W", watts / 1000) }
        return "\(Int(watts.rounded())) W"
    }

    private func kwhString(_ kwh: Double) -> String {
        String(format: "%.1f kWh", kwh)
    }

    private func costString(_ cost: Double?) -> String {
        guard let cost else { return "—" }
        return String(format: "$%.0f", cost)
    }

    private func vramString(_ bytes: Double) -> String {
        String(format: "%.1fG", bytes / 1_073_741_824)
    }

    private func timeString(_ date: Date) -> String {
        Self.timeFormatter.string(from: date)
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()
}

// MARK: - Small primitives

struct MiniBar: View {
    let value: Double
    let color: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(color.opacity(0.16))
                Capsule()
                    .fill(color)
                    .frame(width: geo.size.width * CGFloat(min(max(value / 100, 0), 1)))
            }
        }
    }
}

struct MetricTrendBars: View {
    let values: [Double]
    let color: Color

    var body: some View {
        GeometryReader { geo in
            let maxValue = max(values.max() ?? 0, 1)
            HStack(alignment: .bottom, spacing: 1) {
                ForEach(values.indices, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(color.opacity(0.7))
                        .frame(
                            height: max(
                                1,
                                geo.size.height * CGFloat(values[index]) / CGFloat(maxValue)
                            )
                        )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        }
    }
}

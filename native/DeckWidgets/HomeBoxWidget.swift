import WidgetKit
import SwiftUI

// MARK: - Timeline entry

struct HomeBoxEntry: TimelineEntry {
    let date: Date
    let available: Bool
    let stale: Bool
    let location: String
    let condition: WeatherCondition?
    let days: [WeatherDay]
    let zoneRows: [ZoneRow]
    let settings: HomeBoxSettings
}

// MARK: - Provider
//
// Weather arrives via the agent-pumped snapshot; the world-clock rows are
// computed locally. Staleness windows: fresh <5 min, stale hint 5–30 min,
// unavailable >30 min.

struct HomeBoxProvider: TimelineProvider {
    func placeholder(in context: Context) -> HomeBoxEntry {
        HomeBoxEntry(
            date: .now,
            available: true,
            stale: false,
            location: "Amsterdam",
            condition: WeatherCondition(
                code: 113,
                desc: "Sunny",
                tempC: 23,
                tempF: 73,
                feelsLikeC: 21,
                feelsLikeF: 70,
                humidity: 40,
                windDir: "E",
                windKmph: 8
            ),
            days: [
                WeatherDay(date: "2026-08-13", code: 113, maxTempC: 34, maxTempF: 93, minTempC: 17, minTempF: 63, desc: "Sunny"),
                WeatherDay(date: "2026-08-14", code: 113, maxTempC: 33, maxTempF: 92, minTempC: 20, minTempF: 68, desc: "Sunny"),
                WeatherDay(date: "2026-08-15", code: 176, maxTempC: 27, maxTempF: 81, minTempC: 18, minTempF: 64, desc: "Patchy rain nearby"),
            ],
            zoneRows: ZoneRows.build(identifiers: ["local", "UTC"]),
            settings: HomeBoxSettings()
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (HomeBoxEntry) -> Void) {
        completion(makeEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<HomeBoxEntry>) -> Void) {
        let entry = makeEntry()
        let policy = TimelineReloadPolicy.after(Date().addingTimeInterval(60))
        completion(Timeline(entries: [entry], policy: policy))
    }

    private func makeEntry() -> HomeBoxEntry {
        let snapshot = HomeBoxSnapshotStore.load()
        let settings = DeckSettings.load().homebox
        let now = Date()
        let zoneRows = ZoneRows.build(identifiers: settings.timezoneIDs, at: now)

        guard let snapshot else {
            return HomeBoxEntry(
                date: now,
                available: false,
                stale: false,
                location: "",
                condition: nil,
                days: [],
                zoneRows: zoneRows,
                settings: settings
            )
        }

        let age = now.timeIntervalSince(snapshot.writtenAt)
        let available = age <= 30 * 60
        let stale = age > 5 * 60

        return HomeBoxEntry(
            date: now,
            available: available,
            stale: stale,
            location: snapshot.location,
            condition: snapshot.condition,
            days: snapshot.days,
            zoneRows: zoneRows,
            settings: settings
        )
    }
}

// MARK: - Widget

struct HomeBoxWidget: Widget {
    let kind = "HomeBoxWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: HomeBoxProvider()) { entry in
            HomeBoxWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("HomeBox")
        .description("Weather for your location plus a world clock.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// MARK: - Views

struct HomeBoxWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: HomeBoxEntry

    var body: some View {
        Group {
            if entry.available {
                switch family {
                case .systemSmall:
                    smallView
                case .systemMedium:
                    mediumView
                default:
                    largeView
                }
            } else {
                unavailableView
            }
        }
        .containerBackground(for: .widget) {
            Color.clear
        }
    }

    private var unavailableView: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("HomeBox")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
            Text("No weather data")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
            Text("Waiting for the Deck agent…")
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(.secondary)
            if !entry.zoneRows.isEmpty {
                Divider()
                zoneRowsList
            }
            Spacer(minLength: 0)
        }
    }

    private var smallView: some View {
        VStack(alignment: .leading, spacing: 6) {
            locationLine
            if let condition = entry.condition {
                HStack(spacing: 8) {
                    Image(systemName: WeatherIcon.symbol(for: condition.code))
                        .font(.system(size: 26, weight: .regular))
                        .foregroundStyle(.secondary)
                    Text(tempString(condition.tempC, fahrenheit: condition.tempF))
                        .font(.system(size: 26, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                }
                HStack(spacing: 4) {
                    Text("FEELS")
                        .foregroundStyle(.secondary)
                    Text(tempString(condition.feelsLikeC, fahrenheit: condition.feelsLikeF))
                        .foregroundStyle(.primary)
                }
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .monospacedDigit()
            }
            if !entry.zoneRows.isEmpty {
                Divider()
                zoneRowsList
            }
        }
        .font(.system(size: 12, weight: .semibold, design: .rounded))
        .monospacedDigit()
    }

    private var mediumView: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 14) {
                if let condition = entry.condition {
                    Image(systemName: WeatherIcon.symbol(for: condition.code))
                        .font(.system(size: 22, weight: .regular))
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(tempString(condition.tempC, fahrenheit: condition.tempF))
                            .font(.system(size: 22, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                        HStack(spacing: 4) {
                            Text("FEELS")
                                .foregroundStyle(.secondary)
                            Text(tempString(condition.feelsLikeC, fahrenheit: condition.feelsLikeF))
                                .foregroundStyle(.primary)
                        }
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    }
                }
                Spacer()
                locationLine
                    .multilineTextAlignment(.trailing)
            }

            if entry.settings.showZones && !entry.zoneRows.isEmpty {
                Divider()
                zoneRowsList
            }
            Spacer(minLength: 0)
        }
    }

    private var largeView: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 14) {
                if let condition = entry.condition {
                    Image(systemName: WeatherIcon.symbol(for: condition.code))
                        .font(.system(size: 30, weight: .regular))
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(tempString(condition.tempC, fahrenheit: condition.tempF))
                            .font(.system(size: 30, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                        HStack(spacing: 4) {
                            Text("FEELS")
                                .foregroundStyle(.secondary)
                            Text(tempString(condition.feelsLikeC, fahrenheit: condition.feelsLikeF))
                                .foregroundStyle(.primary)
                        }
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    }
                }
                Spacer()
                locationLine
                    .multilineTextAlignment(.trailing)
            }

            if entry.settings.showForecast && !entry.days.isEmpty {
                Divider()
                forecastStrip
            }

            if entry.settings.showZones && !entry.zoneRows.isEmpty {
                Divider()
                zoneRowsList
            }

            HStack {
                Text("wttr.in")
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(.tertiary)
                Spacer()
            }
            Spacer(minLength: 0)
        }
    }

    private var locationLine: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(entry.location.isEmpty ? "Home" : entry.location)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
            if entry.stale, let writtenAt = snapshotWrittenAt {
                Text("· \(timeString(writtenAt))")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var snapshotWrittenAt: Date? {
        HomeBoxSnapshotStore.load()?.writtenAt
    }

    private var zoneRowsList: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("CLOCKS")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
                .tracking(1)
            ForEach(Array(entry.zoneRows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 6) {
                    Circle()
                        .fill(.teal)
                        .frame(width: 7, height: 7)
                    Text(row.label)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .lineLimit(1)
                    Spacer()
                    Text(row.time)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.primary)
                }
            }
        }
    }

    private var forecastStrip: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("FORECAST")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
                .tracking(1)
            HStack(spacing: 12) {
                ForEach(Array(entry.days.enumerated()), id: \.offset) { _, day in
                    VStack(spacing: 3) {
                        Text(dayLabel(day.date))
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                        Image(systemName: WeatherIcon.symbol(for: day.code))
                            .font(.system(size: 16, weight: .regular))
                            .foregroundStyle(.secondary)
                        HStack(spacing: 2) {
                            Text(tempString(day.maxTempC, fahrenheit: day.maxTempF))
                            Text("·")
                                .foregroundStyle(.tertiary)
                            Text(tempString(day.minTempC, fahrenheit: day.minTempF))
                                .foregroundStyle(.secondary)
                        }
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    // MARK: - Formatting helpers

    private func tempString(_ celsius: Double?, fahrenheit: Double?) -> String {
        guard let value = entry.settings.unitsFahrenheit ? fahrenheit : celsius else { return "–" }
        return "\(Int(value.rounded()))°"
    }

    private func dayLabel(_ date: String) -> String {
        let parts = date.split(separator: "-")
        guard parts.count == 3, let month = Int(parts[1]), let day = Int(parts[2]) else { return date }
        return "\(month)/\(day)"
    }

    private func timeString(_ date: Date) -> String {
        let formatter = Self.timeFormatter
        return formatter.string(from: date)
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}

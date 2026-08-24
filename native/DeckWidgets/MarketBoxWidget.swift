import WidgetKit
import SwiftUI

// MARK: - Timeline entry

struct MarketBoxEntry: TimelineEntry {
    let date: Date
    let available: Bool
    let stale: Bool
    let writtenAt: Date?
    /// One line explaining the last fetch attempt, or nil when all is well.
    let chip: String?
    /// The currency the rows were converted into — shown in the header, so a
    /// settings change mid-tick can never mislabel the data on screen.
    let displayCurrency: MarketCurrency
    let rows: [MarketRow]
    /// Secondary line: unknown symbols and unavailable sources.
    let note: String?
    let settings: MarketBoxSettings
}

// MARK: - Provider
//
// Prices arrive via the agent-pumped snapshot. A snapshot that exists is always
// rendered — the age hint past 5 min and the fetch-status chip carry the
// honesty instead of blanking.

struct MarketBoxProvider: TimelineProvider {
    func placeholder(in context: Context) -> MarketBoxEntry {
        var settings = MarketBoxSettings()
        settings.displayCurrency = .irt
        return MarketBoxEntry(
            date: .now,
            available: true,
            stale: false,
            writtenAt: .now,
            chip: nil,
            displayCurrency: .irt,
            rows: [
                MarketRow(symbol: "BTC", name: "Bitcoin", kind: .crypto, price: 15_600_000_000, dayChangePct: 0.9, sparkline: nil),
                MarketRow(symbol: "USD", name: "US Dollar", kind: .fiat, price: 201_352, dayChangePct: nil, sparkline: nil),
                MarketRow(symbol: "GOLD", name: "Gold", kind: .gold, price: 6_475, dayChangePct: nil, sparkline: nil),
            ],
            note: nil,
            settings: settings
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (MarketBoxEntry) -> Void) {
        completion(makeEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<MarketBoxEntry>) -> Void) {
        let entry = makeEntry()
        let policy = TimelineReloadPolicy.after(Date().addingTimeInterval(60))
        completion(Timeline(entries: [entry], policy: policy))
    }

    private func makeEntry() -> MarketBoxEntry {
        let snapshot = MarketSnapshotStore.load()
        let settings = DeckSettings.load().marketbox
        let now = Date()
        let chip = FetchChip.text(
            source: .marketbox,
            status: FetchStatusStore.load(.marketbox),
            dataWrittenAt: snapshot?.writtenAt,
            now: now
        )

        guard let snapshot else {
            return MarketBoxEntry(
                date: now,
                available: false,
                stale: false,
                writtenAt: nil,
                chip: chip,
                displayCurrency: settings.displayCurrency,
                rows: [],
                note: nil,
                settings: settings
            )
        }

        return MarketBoxEntry(
            date: now,
            available: true,
            stale: now.timeIntervalSince(snapshot.writtenAt) > 5 * 60,
            writtenAt: snapshot.writtenAt,
            chip: chip,
            displayCurrency: snapshot.displayCurrency,
            rows: snapshot.rows,
            note: snapshot.note,
            settings: settings
        )
    }
}

// MARK: - Widget

struct MarketBoxWidget: Widget {
    let kind = "MarketBoxWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: MarketBoxProvider()) { entry in
            MarketBoxWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("MarketBox")
        .description("Live prices for your tickers — crypto, fiat and gold — in USD, Rial or Toman.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// MARK: - Views

struct MarketBoxWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: MarketBoxEntry

    var body: some View {
        Group {
            if entry.available {
                switch family {
                case .systemSmall:
                    listView(maxCount: min(entry.settings.tickerCount, 4), showChange: false)
                case .systemMedium:
                    listView(maxCount: min(entry.settings.tickerCount, 4), showChange: true)
                default:
                    listView(maxCount: entry.settings.tickerCount, showChange: true)
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
            headerLine
            Text("No market data")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
            Text(entry.chip ?? "Waiting for the Deck agent…")
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
    }

    /// Small is price-only (no day change) to keep 4 rows readable; medium and
    /// large carry the change.
    private func listView(maxCount: Int, showChange: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            headerLine
            if entry.rows.isEmpty {
                Text("No market data")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(entry.rows.prefix(maxCount).enumerated()), id: \.offset) { _, row in
                    rowView(row, showChange: showChange)
                }
            }
            if let note = entry.note {
                Text(note)
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 0)
        }
    }

    private var headerLine: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            HStack(spacing: 4) {
                Text("MARKETBOX")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .tracking(1)
                Text(entry.displayCurrency.label)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(entry.settings.accentColor.color)
            }
            Spacer(minLength: 4)
            if let chip = entry.chip {
                Text(chip)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            if entry.stale, let writtenAt = entry.writtenAt {
                Text("· \(timeString(writtenAt))")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func rowView(_ row: MarketRow, showChange: Bool) -> some View {
        HStack(spacing: 6) {
            Text(row.symbol)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .frame(width: 36, alignment: .leading)
                .lineLimit(1)
            Text(MarketPriceFormatter.price(row.price, currency: entry.displayCurrency))
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 2)
            changeLabel(row, showChange: showChange)
        }
    }

    @ViewBuilder
    private func changeLabel(_ row: MarketRow, showChange: Bool) -> some View {
        if showChange, entry.settings.showDayChange, row.kind == .crypto, let pct = row.dayChangePct {
            Text(MarketPriceFormatter.change(pct) ?? "–")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(changeColor(pct))
                .frame(minWidth: 34, alignment: .trailing)
        } else {
            Text("–")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.tertiary)
                .frame(minWidth: 34, alignment: .trailing)
        }
    }

    private func changeColor(_ pct: Double) -> Color {
        if pct > 0.05 { return entry.settings.upColor.color }
        if pct < -0.05 { return entry.settings.downColor.color }
        return .secondary
    }

    private func timeString(_ date: Date) -> String {
        Self.timeFormatter.string(from: date)
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}
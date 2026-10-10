import Foundation
import EventKit

// MARK: - Calendar event search (CalBox)
//
// Title, location, notes and calendar name, a year back and a year ahead, in
// the calendars CalBox uses. Local (EventKit): nothing is sent anywhere. Off by
// default, because event titles would show in a panel that can be on screen
// while sharing — the same reason the clipboard is opt-in.

struct EventHit: Equatable {
    var id: String
    var title: String
    var start: Date
    var end: Date
    var isAllDay: Bool
    var calendarTitle: String
    var location: String
    var notes: String
    /// A known conferencing link found by `CalendarLink`, or empty.
    var meetingURL: String
}

enum EventSearch {
    static let totalLimit = 25
    static let windowDays = 365
    /// Notes can be pages long; matching reads the start of them.
    static let maxNotesLength = 1000

    static func window(now: Date) -> (start: Date, end: Date) {
        let span = TimeInterval(windowDays) * 86_400
        return (now.addingTimeInterval(-span), now.addingTimeInterval(span))
    }

    static func truncatedNotes(_ notes: String?) -> String {
        String((notes ?? "").prefix(maxNotesLength))
    }

    static func results(
        query: String, events: [EventHit], now: Date,
        timeZone: TimeZone = .current, locale: Locale = .current
    ) -> [SearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let day = DateFormatter()
        day.locale = locale; day.timeZone = timeZone; day.dateFormat = "EEE d MMM"
        let dayTime = DateFormatter()
        dayTime.locale = locale; dayTime.timeZone = timeZone; dayTime.dateFormat = "EEE d MMM HH:mm"

        let all = events.compactMap { event -> SearchResult? in
            // A title is what a person is looking for; a location, the notes or
            // the calendar's name are weaker evidence, in that order.
            let relevance = [
                SpotlightMatcher.score(query: trimmed, in: event.title),
                SpotlightMatcher.score(query: trimmed, in: event.location).map { $0 / 2 },
                SpotlightMatcher.score(query: trimmed, in: event.notes).map { $0 / 4 },
                SpotlightMatcher.score(query: trimmed, in: event.calendarTitle).map { $0 / 4 },
            ].compactMap { $0 }.max()
            guard let relevance else { return nil }

            // Among equal matches, the one nearest to today comes first.
            let daysAway = Int(abs(event.start.timeIntervalSince(now)) / 86_400)
            let score = relevance * 1000 + max(0, windowDays - daysAway)

            // The link came out of notes anyone who invites you can write.
            let action: SpotlightAction = DeckLink.webURL(from: event.meetingURL).map(SpotlightAction.open)
                ?? .copy(event.title)

            let when = event.isAllDay
                ? "\(day.string(from: event.start)) · All day"
                : dayTime.string(from: event.start)
            return SearchResult(
                id: "event:\(event.id)",
                provider: .event,
                title: event.title,
                subtitle: [when, event.calendarTitle].filter { !$0.isEmpty }.joined(separator: " · "),
                score: score,
                action: action
            )
        }
        return Array(SpotlightRanking.sorted(all).prefix(totalLimit))
    }
}

/// `EKAuthorizationStatus` raw values are pinned by a test: notDetermined 0,
/// restricted 1, denied 2, fullAccess 3, writeOnly 4. Write-only access cannot
/// read events, so it is a denial here.
enum CalendarAccess {
    static func canRead(rawStatus: Int) -> Bool { rawStatus == 3 }
    static func shouldPrompt(rawStatus: Int) -> Bool { rawStatus == 0 }
}

// MARK: - Reading it (host only — unsandboxed)

enum HostEventSearch {
    /// Every event in the window, in the calendars CalBox is set to read,
    /// reduced to what matching needs. Run off the main actor: EventKit's
    /// `events(matching:)` is synchronous and a two-year window can be large.
    static func events(
        settings: CalBoxSettings, now: Date = Date(), store: EKEventStore = EKEventStore()
    ) async throws -> [EventHit] {
        var status = EKEventStore.authorizationStatus(for: .event).rawValue
        // Prompt only from "never asked", and only because the user typed a
        // calendar search. Anything else that is not full access is a denial.
        if CalendarAccess.shouldPrompt(rawStatus: status) {
            _ = await HostCalendarLoader.requestAccess(store: store)
            status = EKEventStore.authorizationStatus(for: .event).rawValue
        }
        guard CalendarAccess.canRead(rawStatus: status) else { throw SearchSourceFailure(.calendarAccess) }

        return await Task.detached { () -> [EventHit] in
            // Resolved like CalBox does, so search and widget read the same calendars.
            let ids = CalendarDefaults.resolve(
                selected: settings.calendarIDs,
                hasChosen: settings.hasChosenCalendars,
                available: HostCalendarLoader.calendars(store: store).map { ($0.id, $0.allowsContentModifications) })
            let selected = store.calendars(for: .event).filter { ids.contains($0.calendarIdentifier) }
            // An empty `calendars:` predicate means "all calendars"; never pass one.
            guard !selected.isEmpty else { return [] }

            let window = EventSearch.window(now: now)
            let predicate = store.predicateForEvents(withStart: window.start, end: window.end, calendars: selected)
            return store.events(matching: predicate).compactMap { event -> EventHit? in
                guard let start = event.startDate, let end = event.endDate else { return nil }
                let identifier = event.eventIdentifier ?? "\(event.calendar.calendarIdentifier)/\(start.timeIntervalSince1970)"
                return EventHit(
                    id: EventNormalisation.occurrenceID(eventIdentifier: identifier, start: start),
                    title: event.title ?? "(No title)",
                    start: start, end: end,
                    isAllDay: event.isAllDay,
                    calendarTitle: event.calendar.title,
                    location: event.location ?? "",
                    notes: EventSearch.truncatedNotes(event.notes),
                    meetingURL: CalendarLink.meetingURL(
                        url: event.url?.absoluteString, location: event.location, notes: event.notes) ?? "")
            }
        }.value
    }
}

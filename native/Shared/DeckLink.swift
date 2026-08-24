import Foundation

// MARK: - Clickable rows
//
// Every URL a widget row links to arrives from a snapshot file on disk, which
// Deck treats as data rather than as instruction. So one rule governs all of
// them: http(s), with a host, or the row is not a link at all.
//
// This matters more than it looks. On macOS, WidgetKit hands a widget's URL to
// the *containing app* rather than opening it — see `DeckAppDelegate` — so a
// row's destination becomes something Deck itself is asked to open. Narrowing
// it here keeps that from turning Deck into a general-purpose opener for
// whatever a snapshot happens to contain.

enum DeckLink {
    static func webURL(from raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let url = URL(string: trimmed) else { return nil }
        return webURL(from: url)
    }

    static func webURL(from url: URL) -> URL? {
        guard let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http" else {
            return nil
        }
        guard url.host?.isEmpty == false else { return nil }
        return url
    }
}

// MARK: - Finding a calendar event's meeting link
//
// `EKEvent.url` is the field this should read, and on a real account it is
// simply empty: measured across 10 events from a synced Google calendar, 0 set
// `url`, 0 had a URL in `location`, and 9 carried one in `notes`. So the notes
// are where the link lives.
//
// The notes are not one link, though. Every invite in that sample contained
// three hosts:
//
//     meet.google.com    the call
//     support.google.com "Learn more about Meet"
//     tel.meet           dial-in numbers
//
// Taking "the first URL in the notes" would therefore open a help page from a
// click on a meeting. Known conferencing hosts are matched instead, and an
// event with none is not a link at all — a row that opens the wrong page is
// worse than a row that does nothing.

enum CalendarLink {
    /// Hosts that mean "this is the call". Matched exactly or as a subdomain,
    /// never as a substring: `zoom.us.evil.com` must not pass.
    private static let meetingHosts = [
        "meet.google.com",
        "zoom.us",
        "teams.microsoft.com",
        "teams.live.com",
        "webex.com",
        "whereby.com",
        "chime.aws",
        "gotomeeting.com",
        "bluejeans.com",
        "meet.jit.si",
    ]

    /// In priority order: the event's own URL, then a link in the location
    /// (where Zoom and Teams often put it), then a recognised conferencing
    /// host in the notes.
    static func meetingURL(url: String?, location: String?, notes: String?) -> String? {
        if let url, let web = DeckLink.webURL(from: url) {
            return web.absoluteString
        }
        if let location, let web = DeckLink.webURL(from: location) {
            return web.absoluteString
        }
        if let location, let found = firstMeetingHost(in: location) {
            return found
        }
        if let notes, let found = firstMeetingHost(in: notes) {
            return found
        }
        return nil
    }

    private static func firstMeetingHost(in text: String) -> String? {
        for url in webURLs(in: text) where isMeetingHost(url.host) {
            return url.absoluteString
        }
        return nil
    }

    private static func isMeetingHost(_ host: String?) -> Bool {
        guard let host = host?.lowercased() else { return false }
        return meetingHosts.contains { host == $0 || host.hasSuffix(".\($0)") }
    }

    private static func webURLs(in text: String) -> [URL] {
        guard let detector = try? NSDataDetector(
            types: NSTextCheckingResult.CheckingType.link.rawValue
        ) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return detector
            .matches(in: text, range: range)
            .compactMap(\.url)
            .compactMap { DeckLink.webURL(from: $0) }
    }
}

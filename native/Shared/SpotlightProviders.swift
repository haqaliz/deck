import Foundation

// MARK: - Spotlight providers
//
// One pure function per source, over the snapshot the widget already renders.
// None of them reads a file, touches the pasteboard or opens a socket: the
// host loads the snapshots and hands them in, which is what keeps this slice
// free of network code and testable without a container.
//
// A nil snapshot means "that source has nothing yet" and yields no results —
// never an error row.

enum ClipSearch {
    static func results(query: String, snapshot: ClipBoxSnapshot?) -> [SearchResult] {
        guard let snapshot else { return [] }
        return snapshot.items.compactMap { item in
            // Nothing to copy back for an image or "other" item, so a row for
            // one would be a row whose Enter does nothing.
            guard let content = item.content, !content.isEmpty else { return nil }
            guard let score = [content, item.preview, item.detail]
                .compactMap({ SpotlightMatcher.score(query: query, in: $0) })
                .max()
            else { return nil }
            return SearchResult(
                id: "clip:\(item.id.uuidString)",
                provider: .clip,
                title: item.preview.isEmpty ? content : item.preview,
                subtitle: item.detail,
                score: score,
                action: .copy(content)
            )
        }
    }
}

enum DevSearch {
    static func results(query: String, snapshot: DevBoxSnapshot?) -> [SearchResult] {
        guard let snapshot else { return [] }
        var out: [SearchResult] = []

        for port in snapshot.ports {
            let haystack = "\(port.port) \(port.command) \(port.host)"
            guard let score = SpotlightMatcher.score(query: query, in: haystack) else { continue }
            out.append(SearchResult(
                id: "port:\(port.host):\(port.port):\(port.command)",
                provider: .port,
                title: "\(port.command) :\(port.port)",
                subtitle: port.host,
                score: score,
                action: .copy(String(port.port))
            ))
        }

        for container in snapshot.containers {
            let haystack = "\(container.name) \(container.image)"
            guard let score = SpotlightMatcher.score(query: query, in: haystack) else { continue }
            out.append(SearchResult(
                // A different prefix from ports: a container and a process can
                // share a name ("redis"), and one id would collapse both rows.
                id: "container:\(container.name)",
                provider: .port,
                title: container.name,
                subtitle: "\(container.image) · \(container.status)",
                score: score,
                action: .copy(container.name)
            ))
        }
        return out
    }
}

enum ClockSearch {
    /// Searches the curated city list plus whatever the user has configured, so
    /// a zone added by hand is findable too. A configured id that is also
    /// curated is listed once.
    static func results(
        query: String,
        configuredIDs: [String],
        now: Date,
        reference: TimeZone
    ) -> [SearchResult] {
        var candidates = ClockBoxCities.curated.map { (id: $0.id, name: $0.displayName) }
        for id in configuredIDs where ClockBoxCore.resolve(id: id) != nil
            && !candidates.contains(where: { $0.id == id }) {
            candidates.append((id: id, name: ClockBoxCore.displayName(id: id)))
        }

        return candidates.compactMap { candidate in
            guard ClockBoxCore.resolve(id: candidate.id) != nil,
                  let score = SpotlightMatcher.score(query: query, in: "\(candidate.name) \(candidate.id)")
            else { return nil }
            let time = ClockBoxCore.timeLabel(id: candidate.id, at: now)
            let day = ClockBoxCore.relativeDay(id: candidate.id, relativeTo: reference, at: now)
            let offset = ClockBoxCore.offsetLabel(id: candidate.id, relativeTo: reference, at: now)
            return SearchResult(
                id: "time:\(candidate.id)",
                provider: .time,
                title: candidate.name,
                subtitle: "\(time) · \(day.label) · \(offset)",
                score: score,
                action: .copy(time)
            )
        }
    }
}

enum OpenCodeSearch {
    /// Recent sessions only — the snapshot holds a short list, not the whole
    /// database. The settings copy says so.
    static func results(query: String, snapshot: OpenCodeSnapshot?) -> [SearchResult] {
        guard let snapshot else { return [] }
        return snapshot.sessionList.enumerated().compactMap { index, session in
            guard let score = SpotlightMatcher.score(query: query, in: session.title) else { return nil }
            return SearchResult(
                // Two sessions can share a title; the position keeps the ids apart.
                id: "oc:\(index):\(session.title)",
                provider: .oc,
                title: session.title,
                subtitle: "\(session.input + session.output) tokens",
                score: score,
                action: .copy(session.title)
            )
        }
    }
}

// MARK: - Engine

/// Everything the engine reads, loaded by the host at query time.
struct SpotlightInputs {
    var clip: ClipBoxSnapshot?
    var devbox: DevBoxSnapshot?
    var opencode: OpenCodeSnapshot?
    var configuredClockIDs: [String]
}

enum SpotlightEngine {
    static let perSectionLimit = 5
    /// A scoped query is one section, so it can afford more rows.
    static let scopedLimit = 10

    static func run(
        rawQuery: String,
        settings: SpotlightSettings,
        inputs: SpotlightInputs,
        now: Date,
        reference: TimeZone
    ) -> [SearchSection] {
        let query = SpotlightQuery.parse(rawQuery)
        guard !query.isEmpty else { return [] }

        // A disabled provider is never searched — not even when the user types
        // its prefix. The toggle is the privacy control for the clipboard.
        let providers = SearchProviderID.localCases.filter { id in
            settings.isEnabled(id) && (query.scope == nil || query.scope == id)
        }

        var results: [SearchResult] = []
        for provider in providers {
            switch provider {
            case .clip: results += ClipSearch.results(query: query.text, snapshot: inputs.clip)
            case .port: results += DevSearch.results(query: query.text, snapshot: inputs.devbox)
            case .time:
                results += ClockSearch.results(
                    query: query.text, configuredIDs: inputs.configuredClockIDs,
                    now: now, reference: reference)
            case .oc: results += OpenCodeSearch.results(query: query.text, snapshot: inputs.opencode)
            case .task: break  // remote: answered by the host through RemoteSearchPolicy
            }
        }
        return SpotlightRanking.sections(
            from: results,
            perSectionLimit: query.scope == nil ? perSectionLimit : scopedLimit
        )
    }
}

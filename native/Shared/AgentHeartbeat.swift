import Foundation

// MARK: - The 60s agent's liveness witness
//
// `com.deck.agent` writes ten snapshots and the host app writes every one of
// them too, so none of them can distinguish "the agent ran" from "Deck was
// open". This file is the one thing only the agent writes.
//
// **It is a file, not a field on `DeckSettings`, and that is load-bearing.**
// `ContainerMigration` carries only `settings.json` across the bundle rename
// (deliberately — everything else is rebuilt within one 60s tick). A field
// would arrive in the new container holding a timestamp from the old install,
// with an agent that has never run there: the exact false positive
// `AgentRegistrationClock` exists to prevent, one file over.

struct AgentHeartbeat: Codable, Equatable {
    /// When the 60s agent last **started** a full refresh.
    ///
    /// Deliberately the start and not the end. The full path awaits ~10 mostly
    /// serial sources at 10s timeouts each, so a slow-but-healthy tick could
    /// otherwise cross the staleness limit and be reported dead — while a
    /// start-write catches strictly more: launchd starts no new tick while one
    /// is still running, so a hung agent stops advancing this either way.
    var writtenAt: Date
}

enum AgentHeartbeatStore {
    static var fileURL: URL {
        DeckSettings.containerDirectory.appendingPathComponent("agent-heartbeat.json")
    }

    static func evidence(at url: URL = fileURL) -> AgentEvidence {
        AgentEvidenceReader.read(at: url) {
            try? JSONDecoder().decode(AgentHeartbeat.self, from: $0).writtenAt
        }
    }

    static func save(_ heartbeat: AgentHeartbeat, to url: URL = fileURL) {
        guard let data = try? JSONEncoder().encode(heartbeat) else { return }
        _ = AtomicFile.write(data, to: url)
    }
}

/// Reads a witness file into `AgentEvidence`, checking **existence before
/// decoding** so the two failures stay apart.
///
/// The obvious shape — `try? Data(contentsOf:)` then `try? decode`, both to
/// `nil` — is what `ProcessSnapshotStore.load()` does, and it is why a truncated
/// snapshot from a crash mid-write reads as an agent that never ran.
enum AgentEvidenceReader {
    static func read(at url: URL, timestamp: (Data) -> Date?) -> AgentEvidence {
        guard FileManager.default.fileExists(atPath: url.path) else { return .never }
        guard let data = try? Data(contentsOf: url), let date = timestamp(data) else {
            return .unreadable
        }
        return .ran(at: date)
    }
}

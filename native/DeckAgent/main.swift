import Foundation
import OSLog

// MARK: - DeckAgent
//
// Silent CLI that refreshes the widget data snapshots (opencode usage +
// top processes) into the extension container, then exits. Runs from a
// LaunchAgent every N seconds — no window, no Dock icon, no flicker.
//
// Modes:
//   (default)      full refresh: every snapshot, launched by com.deck.agent
//   --processes    process snapshot only, launched by com.deck.agent.processes
//                  at the LiveBox process refresh interval (default 15s)
//
// Logging: one OSLog line per snapshot (written/skipped/failed) so a soak run
// is auditable via `log show --predicate 'subsystem == "com.deck.agent"'`.
// Never logs URLs, tokens, repo names, or paths — only snapshot names and
// outcomes.

let semaphore = DispatchSemaphore(value: 0)

private let agentLog = Logger(subsystem: "com.deck.agent", category: "DeckAgent")

func sampleProcesses() {
    let processes = ProcessSnapshot(writtenAt: Date(), processes: HostProcessSampler.top(limit: 10))
    if processes != ProcessSnapshotStore.load() {
        ProcessSnapshotStore.save(processes)
        agentLog.info("written processes snapshot")
    } else {
        agentLog.info("skipped processes snapshot (unchanged)")
    }
}

Task {
    if CommandLine.arguments.contains("--processes") {
        sampleProcesses()
        semaphore.signal()
        exit(0)
    }

    let start = Date()
    agentLog.info("full refresh started")

    let settings = DeckSettings.load()

    let opencode: OpenCodeSnapshot?
    if let serverURL = settings.openbox.serverURL, !serverURL.isEmpty {
        // Remote mode: never passes a default token — without the user's own
        // token no data is fetched (no silent local-DB fallback).
        if !settings.openbox.token.isEmpty {
            opencode = try? await RemoteOpenCodeLoader.load(serverURL: serverURL, token: settings.openbox.token)
        } else {
            opencode = nil
        }
    } else {
        opencode = OpenCodeReader.load()
    }
    if let opencode {
        if opencode != OpenCodeSnapshotStore.load() {
            OpenCodeSnapshotStore.save(opencode)
            agentLog.info("written opencode snapshot")
        } else {
            agentLog.info("skipped opencode snapshot (unchanged)")
        }
    } else {
        agentLog.info("failed opencode snapshot (unavailable or no token)")
    }

    if let gitbox = HostGitBoxSampler.snapshot(
        paths: settings.gitbox.repoPaths,
        scanDepth: settings.gitbox.scanDepth
    ) {
        if gitbox != GitBoxSnapshotStore.load() {
            GitBoxSnapshotStore.save(gitbox)
            agentLog.info("written gitbox snapshot")
        } else {
            agentLog.info("skipped gitbox snapshot (unchanged)")
        }
    } else {
        agentLog.info("failed gitbox snapshot (unavailable)")
    }

    if let devbox = HostDevBoxSampler.snapshot() {
        if devbox != DevBoxSnapshotStore.load() {
            DevBoxSnapshotStore.save(devbox)
            agentLog.info("written devbox snapshot")
        } else {
            agentLog.info("skipped devbox snapshot (unchanged)")
        }
    } else {
        agentLog.info("failed devbox snapshot (unavailable)")
    }

    if let clipbox = HostClipBoardSampler.snapshot(maxCount: settings.clipbox.historyCount) {
        // Always written: the sampler refreshes writtenAt every tick so the
        // widget's staleness window stays honest on quiet days.
        ClipBoxSnapshotStore.save(clipbox)
        agentLog.info("written clipbox snapshot")
    } else {
        agentLog.info("failed clipbox snapshot (unavailable)")
    }

    if let homebox = try? await HostWeatherLoader.fetch(location: settings.homebox.location) {
        // Always written: writtenAt drives the widget's staleness windows, so
        // a successful fetch must refresh it even when weather is unchanged.
        HomeBoxSnapshotStore.save(homebox)
        agentLog.info("written weather snapshot")
    } else {
        agentLog.info("failed weather snapshot (network unavailable)")
    }

    // ShipBox: requires the user's own repo + token — never a default token.
    let shipboxRepo = settings.shipbox.repo
        .trimmingCharacters(in: .whitespacesAndNewlines)
    if !shipboxRepo.isEmpty && !settings.shipbox.token.isEmpty {
        if let shipbox = try? await HostGitHubLoader.fetch(
            repo: shipboxRepo,
            token: settings.shipbox.token
        ) {
            // Always written: writtenAt drives the staleness windows.
            ShipBoxSnapshotStore.save(shipbox)
            agentLog.info("written shipbox snapshot")
        } else {
            agentLog.info("failed shipbox snapshot (network or API unavailable)")
        }
    } else {
        agentLog.info("skipped shipbox snapshot (not configured)")
    }

    let elapsed = Date().timeIntervalSince(start)
    agentLog.info("full refresh done in \(elapsed, format: .fixed(precision: 2))s")
    semaphore.signal()
}

semaphore.wait()
exit(0)

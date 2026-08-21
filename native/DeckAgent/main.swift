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
            do {
                opencode = try await RemoteOpenCodeLoader.load(serverURL: serverURL, token: settings.openbox.token)
                FetchStatusStore.record(.ok, for: .opencodeRemote)
            } catch {
                opencode = nil
                let outcome = FetchClassifier.outcome(for: error)
                FetchStatusStore.record(outcome, for: .opencodeRemote)
                agentLog.info("failed opencode fetch (\(outcome.rawValue, privacy: .public))")
            }
        } else {
            opencode = nil
            FetchStatusStore.record(.notConfigured, for: .opencodeRemote)
        }
    } else {
        opencode = OpenCodeReader.load()
        // Local mode shows no chip, but a stale remote failure must not
        // outlive the mode that produced it.
        if opencode != nil {
            FetchStatusStore.record(.ok, for: .opencodeRemote)
        }
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

    do {
        // Always written: writtenAt drives the widget's staleness windows, so
        // a successful fetch must refresh it even when weather is unchanged.
        let homebox = try await HostWeatherLoader.fetch(location: settings.homebox.location)
        HomeBoxSnapshotStore.save(homebox)
        FetchStatusStore.record(.ok, for: .weather)
        agentLog.info("written weather snapshot")
    } catch {
        let outcome = FetchClassifier.outcome(for: error)
        FetchStatusStore.record(outcome, for: .weather)
        agentLog.info("failed weather snapshot (\(outcome.rawValue, privacy: .public))")
    }

    // ShipBox: requires the user's own repo + token — never a default token.
    let shipboxRepo = settings.shipbox.repo
        .trimmingCharacters(in: .whitespacesAndNewlines)
    if !shipboxRepo.isEmpty && !settings.shipbox.token.isEmpty {
        do {
            // Always written: writtenAt drives the staleness windows.
            let shipbox = try await HostGitHubLoader.fetch(
                repo: shipboxRepo,
                token: settings.shipbox.token
            )
            ShipBoxSnapshotStore.save(shipbox)
            FetchStatusStore.record(.ok, for: .shipbox)
            agentLog.info("written shipbox snapshot")
        } catch {
            let outcome = FetchClassifier.outcome(for: error)
            FetchStatusStore.record(outcome, for: .shipbox)
            agentLog.info("failed shipbox snapshot (\(outcome.rawValue, privacy: .public))")
        }
    } else {
        // Recorded, not just logged: "you haven't set this up" is the most
        // fixable state there is, and the widget can only say so if it lands
        // in the container.
        FetchStatusStore.record(.notConfigured, for: .shipbox)
        agentLog.info("skipped shipbox snapshot (not configured)")
    }

    // TaskBox: requires the user's own org + project + PAT — never a default token.
    let taskboxOrg = settings.taskbox.organization
        .trimmingCharacters(in: .whitespacesAndNewlines)
    let taskboxProject = settings.taskbox.project
        .trimmingCharacters(in: .whitespacesAndNewlines)
    if !taskboxOrg.isEmpty && !taskboxProject.isEmpty && !settings.taskbox.token.isEmpty {
        do {
            // Always written: writtenAt drives the staleness windows, so a
            // successful fetch must refresh it even when the task list is
            // unchanged — otherwise a quiet day reads as a stale widget.
            let taskbox = try await HostAzureDevOpsLoader.fetch(
                organization: taskboxOrg,
                project: taskboxProject,
                token: settings.taskbox.token
            )
            TaskBoxSnapshotStore.save(taskbox)
            FetchStatusStore.record(.ok, for: .taskbox)
            agentLog.info("written taskbox snapshot")
        } catch {
            let outcome = FetchClassifier.outcome(for: error)
            FetchStatusStore.record(outcome, for: .taskbox)
            agentLog.info("failed taskbox snapshot (\(outcome.rawValue, privacy: .public))")
        }
    } else {
        FetchStatusStore.record(.notConfigured, for: .taskbox)
        agentLog.info("skipped taskbox snapshot (not configured)")
    }

    // CalBox: needs a granted TCC prompt; the loader resolves which calendars
    // to read, so a widget added before settings were ever opened still shows
    // real events. Never logs event titles — only counts and outcomes.
    do {
        // Always written: writtenAt drives the staleness window and the
        // "Agent hasn't run" chip, so a quiet calendar must still refresh it.
        let calbox = try await HostCalendarLoader.fetch(settings: settings.calbox)
        CalBoxSnapshotStore.save(calbox)
        FetchStatusStore.record(.ok, for: .calbox)
        agentLog.info("written calbox snapshot (\(calbox.events.count, privacy: .public) events)")
    } catch {
        let outcome = FetchClassifier.outcome(for: error)
        FetchStatusStore.record(outcome, for: .calbox)
        agentLog.info("failed calbox snapshot (\(outcome.rawValue, privacy: .public))")
    }

    let elapsed = Date().timeIntervalSince(start)
    agentLog.info("full refresh done in \(elapsed, format: .fixed(precision: 2))s")
    semaphore.signal()
}

semaphore.wait()
exit(0)

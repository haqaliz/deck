import Foundation

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

let semaphore = DispatchSemaphore(value: 0)

func sampleProcesses() {
    let processes = ProcessSnapshot(writtenAt: Date(), processes: HostProcessSampler.top(limit: 10))
    if processes != ProcessSnapshotStore.load() {
        ProcessSnapshotStore.save(processes)
    }
}

Task {
    if CommandLine.arguments.contains("--processes") {
        sampleProcesses()
        semaphore.signal()
        exit(0)
    }

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
    if let opencode, opencode != OpenCodeSnapshotStore.load() {
        OpenCodeSnapshotStore.save(opencode)
    }

    if let gitbox = HostGitBoxSampler.snapshot(
        paths: settings.gitbox.repoPaths,
        scanDepth: settings.gitbox.scanDepth
    ), gitbox != GitBoxSnapshotStore.load() {
        GitBoxSnapshotStore.save(gitbox)
    }

    if let devbox = HostDevBoxSampler.snapshot(), devbox != DevBoxSnapshotStore.load() {
        DevBoxSnapshotStore.save(devbox)
    }

    if let clipbox = HostClipBoardSampler.snapshot(maxCount: settings.clipbox.historyCount) {
        // Always written: the sampler refreshes writtenAt every tick so the
        // widget's staleness window stays honest on quiet days.
        ClipBoxSnapshotStore.save(clipbox)
    }

    if let homebox = try? await HostWeatherLoader.fetch(location: settings.homebox.location) {
        // Always written: writtenAt drives the widget's staleness windows, so
        // a successful fetch must refresh it even when weather is unchanged.
        HomeBoxSnapshotStore.save(homebox)
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
        }
    }

    semaphore.signal()
}

semaphore.wait()
exit(0)

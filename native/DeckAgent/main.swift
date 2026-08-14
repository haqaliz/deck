import Foundation

// MARK: - DeckAgent
//
// Silent CLI that refreshes the widget data snapshots (opencode usage +
// top processes) into the extension container, then exits. Runs from a
// LaunchAgent every N seconds — no window, no Dock icon, no flicker.

let semaphore = DispatchSemaphore(value: 0)

Task {
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

    let processes = ProcessSnapshot(writtenAt: Date(), processes: HostProcessSampler.top(limit: 10))
    if processes != ProcessSnapshotStore.load() {
        ProcessSnapshotStore.save(processes)
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

    semaphore.signal()
}

semaphore.wait()
exit(0)

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
//                  at the LiveBox process refresh interval (default 15s);
//                  the SMAppService-launched instance selects this mode via
//                  the DECK_AGENT_ROLE=processes environment variable instead
//                  (BundleProgram plists cannot carry arguments)
//
// Logging: one OSLog line per snapshot (written/skipped/failed) so a soak run
// is auditable via `log show --predicate 'subsystem == "<DeckBundle.logSubsystem>"'`.
// Never logs URLs, tokens, repo names, or paths — only snapshot names and
// outcomes.

// Carry settings across the container move the bundle rename forces, before
// anything below reads them. The agent is registered at login and the app is
// not, so on an upgraded install the agent can genuinely run first. Inert
// until the rename ships; idempotent and never overwriting afterwards.
ContainerMigration.run()

let semaphore = DispatchSemaphore(value: 0)

private let agentLog = Logger(subsystem: DeckBundle.logSubsystem, category: "DeckAgent")

func sampleProcesses() {
    // The launchd tick is a fixed 5s (the plist is sealed in the signed
    // bundle), so the configured interval is enforced here: skip the sample
    // entirely until the configured cadence has elapsed. Always written when
    // sampled — writtenAt drives both the throttle and the widget's staleness
    // window, so a quiet machine keeps a fresh snapshot instead of the process
    // rows going empty.
    let interval = DeckSettings.load().livebox.processRefreshInterval
    let lastSampleAt = ProcessSnapshotStore.load()?.writtenAt
    guard ProcessRefreshPolicy.shouldSample(
        lastSampleAt: lastSampleAt, configuredInterval: interval, now: Date()
    ) else {
        agentLog.info("skipped processes snapshot (throttled)")
        return
    }
    let processes = ProcessSnapshot(writtenAt: Date(), processes: HostProcessSampler.top(limit: 10))
    ProcessSnapshotStore.save(processes)
    agentLog.info("written processes snapshot")
}

Task {
    let fastAgent = ProcessInfo.processInfo.environment["DECK_AGENT_ROLE"] == "processes"
        || CommandLine.arguments.contains("--processes")
    if fastAgent {
        sampleProcesses()
        semaphore.signal()
        exit(0)
    }

    let start = Date()
    agentLog.info("full refresh started")

    // The 60s agent's liveness witness, and the ONLY file it alone writes —
    // every snapshot below is written by the host app too, which is why a dead
    // agent used to be invisible while Deck was open.
    //
    // Written HERE, before any fetch, and deliberately not at the end: this path
    // awaits ~10 mostly serial sources at 10s timeouts each, so an end-write
    // would let a slow-but-healthy tick cross the staleness limit and be
    // reported dead. It witnesses that this agent was launched and started
    // work — never that it finished — and that is the honest claim, because
    // launchd starts no new tick while one is still running, so a hung agent
    // stops advancing this stamp either way.
    AgentHeartbeatStore.save(AgentHeartbeat(writtenAt: start))
    agentLog.info("written agent heartbeat")

    var settings = DeckSettings.load()
    // The five API credentials live in the keychain, not in settings.json.
    // A key that FAILED to read (a locked login keychain) is not the same as
    // one that was never set: it is recorded as its own outcome here, and every
    // gate below skips rather than falling through to "not configured", which
    // would tell the user to paste a token they already pasted.
    let unavailableAccounts = settings.hydrateAccountsFromKeychain()
    let unavailableLegacy = settings.hydrateFromKeychain()
    let credentialGates = Dictionary(uniqueKeysWithValues: CredentialSlot.allCases.map {
        ($0, settings.gate($0, unavailableAccounts: unavailableAccounts,
                           unavailableLegacySecrets: unavailableLegacy))
    })
    for slot in CredentialSlot.allCases where credentialGates[slot] == .unavailable {
        FetchStatusStore.record(.credentialsUnavailable, for: slot.source)
        agentLog.info("credential unavailable (\(slot.rawValue, privacy: .public))")
    }

    let opencode: OpenCodeSnapshot?
    if settings.openBoxUsesRemoteServer {
        // Remote mode: never passes a default token — without the user's own
        // token no data is fetched (no silent local-DB fallback).
        switch credentialGates[.openbox] {
        case .fetch(let credential):
            do {
                let state = OpenCodeSyncStore.load()
                let (remote, newState) = try await RemoteOpenCodeLoader.load(
                    serverURL: credential.serverURL, token: credential.token, state: state
                )
                opencode = remote
                // Persist the incremental cursor only when it changed — an
                // idle tick writes nothing. Failure above leaves the old file
                // in place; the next tick's overlapping merge is idempotent.
                if let newState, newState != state {
                    OpenCodeSyncStore.save(newState)
                }
                FetchStatusStore.record(.ok, for: .opencodeRemote)
            } catch {
                opencode = nil
                let outcome = FetchClassifier.outcome(for: error)
                FetchStatusStore.record(outcome, for: .opencodeRemote)
                agentLog.info("failed opencode fetch (\(outcome.rawValue, privacy: .public))")
            }
        case .unavailable:
            // Outcome already recorded above; do not overwrite it.
            opencode = nil
        default:
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
        let weather = try await HostWeatherLoader.fetch(location: settings.weatherbox.location)
        WeatherSnapshotStore.save(weather)
        FetchStatusStore.record(.ok, for: .weather)
        agentLog.info("written weather snapshot")
    } catch {
        let outcome = FetchClassifier.outcome(for: error)
        FetchStatusStore.record(outcome, for: .weather)
        agentLog.info("failed weather snapshot (\(outcome.rawValue, privacy: .public))")
    }

    // ShipBox: requires the user's own token — never a default one. Dynamic
    // mode needs nothing else; static mode also needs at least one repo.
    let shipbox = settings.shipbox
    let shipboxHasATarget = shipbox.repoMode == .dynamic || !shipbox.repos.isEmpty
    if credentialGates[.shipbox] == .unavailable {
        agentLog.info("skipped shipbox snapshot (credential unavailable)")
    } else if case .fetch(let credential)? = credentialGates[.shipbox], shipboxHasATarget {
        do {
            // Always written: writtenAt drives the staleness windows. A repo
            // that failed while others succeeded rides in the snapshot's note
            // rather than failing the whole fetch.
            let snapshot = try await HostGitHubLoader.fetch(settings: shipbox, token: credential.token)
            ShipBoxSnapshotStore.save(snapshot)
            FetchStatusStore.record(.ok, for: .shipbox)
            // Counts only, never repo names: a private repo's name is exactly
            // the kind of thing that should not land in the system log.
            agentLog.info("written shipbox snapshot (\(snapshot.repos.count, privacy: .public) repos, \(snapshot.runs.count, privacy: .public) runs)")
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
    if credentialGates[.taskbox] == .unavailable {
        agentLog.info("skipped taskbox snapshot (credential unavailable)")
    } else if case .fetch(let credential)? = credentialGates[.taskbox] {
        do {
            // Always written: writtenAt drives the staleness windows, so a
            // successful fetch must refresh it even when the task list is
            // unchanged — otherwise a quiet day reads as a stale widget.
            let taskbox = try await HostAzureDevOpsLoader.fetch(
                organization: credential.organization,
                projects: credential.projects,
                token: credential.token
            )
            TaskBoxSnapshotStore.save(taskbox)
            FetchStatusStore.record(.ok, for: .taskbox)
            // Counts and outcomes only — never a project name.
            agentLog.info(
                "written taskbox snapshot (\(credential.projects.count, privacy: .public) projects)"
            )
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

    // PRBox: two providers at once, each with its own credentials and its own
    // fetch-status key. A provider that fails must not blank the other's rows
    // — half a review queue is still worth reading, and the chip names the
    // half that is missing. A provider that is switched off records .ok rather
    // than .notConfigured, which is what clears a failure it left behind.
    let prbox = settings.prbox
    var githubTotals: PRRoleTotals?
    switch credentialGates[.prboxGitHub] {
    case .fetch(let credential):
        do {
            githubTotals = try await HostGitHubPRLoader.fetch(
                token: credential.token,
                scope: prbox.github.scope,
                cap: prbox.prCount,
                reviewState: prbox.showReviewState
            )
            FetchStatusStore.record(.ok, for: .prboxGitHub)
        } catch {
            let outcome = FetchClassifier.outcome(for: error)
            FetchStatusStore.record(outcome, for: .prboxGitHub)
            agentLog.info("failed prbox github (\(outcome.rawValue, privacy: .public))")
        }
    case .unavailable:
        break // Outcome already recorded above.
    case .some(let gate):
        // `.off` records `ok`, which is what clears a failure the provider
        // left behind when it was still on; `.notConfigured` says so plainly.
        if let outcome = gate.outcome { FetchStatusStore.record(outcome, for: .prboxGitHub) }
    case nil:
        break
    }

    var azureTotals: PRRoleTotals?
    switch credentialGates[.prboxAzure] {
    case .fetch(let credential):
        do {
            azureTotals = try await HostAzurePRLoader.fetch(
                organization: credential.organization,
                projects: credential.projects,
                token: credential.token,
                cap: prbox.prCount
            )
            FetchStatusStore.record(.ok, for: .prboxAzure)
        } catch {
            let outcome = FetchClassifier.outcome(for: error)
            FetchStatusStore.record(outcome, for: .prboxAzure)
            agentLog.info("failed prbox azure (\(outcome.rawValue, privacy: .public))")
        }
    case .unavailable:
        break // Outcome already recorded above.
    case .some(let gate):
        if let outcome = gate.outcome { FetchStatusStore.record(outcome, for: .prboxAzure) }
    case nil:
        break
    }

    if githubTotals != nil || azureTotals != nil {
        // Always written: writtenAt drives the staleness window and the
        // "Agent hasn't run" chip, so an empty queue must still refresh it.
        let snapshot = PRSnapshotBuilder.build(
            github: githubTotals, azure: azureTotals, cap: prbox.prCount, now: Date()
        )
        PRBoxSnapshotStore.save(snapshot)
        agentLog.info("written prbox snapshot (\(snapshot.pullRequests.count, privacy: .public) rows)")
    } else {
        agentLog.info("skipped prbox snapshot (nothing fetched)")
    }

    // MarketBox: live prices for the configured symbols in the display
    // currency. No tokens anywhere — every source is keyless. The loader only
    // throws when no row at all could be priced; partial results render with a
    // note instead. Always written: writtenAt drives the staleness windows.
    do {
        let marketbox = try await HostMarketLoader.fetch(settings: settings.marketbox)
        MarketSnapshotStore.save(marketbox)
        FetchStatusStore.record(.ok, for: .marketbox)
        agentLog.info("written marketbox snapshot (\(marketbox.rows.count, privacy: .public) rows)")
    } catch {
        let outcome = FetchClassifier.outcome(for: error)
        FetchStatusStore.record(outcome, for: .marketbox)
        agentLog.info("failed marketbox snapshot (\(outcome.rawValue, privacy: .public))")
    }

    let elapsed = Date().timeIntervalSince(start)
    agentLog.info("full refresh done in \(elapsed, format: .fixed(precision: 2))s")
    semaphore.signal()
}

semaphore.wait()
exit(0)

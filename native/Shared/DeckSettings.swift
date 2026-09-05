import Foundation
import SwiftUI

// MARK: - Color (Codable RGBA)

struct RGBA: Codable, Equatable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double

    init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    /// Resolve a SwiftUI `Color` into fixed components.
    ///
    /// **Main actor on purpose.** `NSColor(color)` is not thread-safe: calling
    /// it concurrently corrupts an `NSMapTable` inside Foundation and aborts
    /// the process. This used to be reachable from `DeckSettings`' decode path
    /// — i.e. from `DeckAgent` and every widget timeline — which is how it
    /// crashed in production. The isolation makes that a compile error rather
    /// than a race, and leaves the one legitimate caller: a `ColorPicker`
    /// writing the user's pick back, which SwiftUI always does on the main
    /// thread. Defaults must use the fixed palette below, never this.
    @MainActor
    init(_ color: Color) {
        let ns = NSColor(color).usingColorSpace(.sRGB) ?? .white
        red = Double(ns.redComponent)
        green = Double(ns.greenComponent)
        blue = Double(ns.blueComponent)
        alpha = Double(ns.alphaComponent)
    }

    var color: Color {
        Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }
}

// MARK: - The default palette

/// Deck's default colours, as literal sRGB components.
///
/// These are **snapshots** of Apple's system colours under the aqua
/// appearance, measured on macOS 15, and they are deliberately not re-resolved
/// at runtime. Two reasons, both bugs that the old `RGBA.systemGreen` defaults had:
///
/// 1. **`init(_ color: Color)` is not thread-safe.** It bridges through
///    `NSColor`, and building a struct's defaults meant running that bridge
///    during *decode* — from the app, from `DeckAgent` and from every widget
///    timeline at once. Captured in production 2026-08-26: `SIGABRT`, malloc
///    corruption inside `-[NSConcreteMapTable grow]`.
/// 2. **System colours are appearance-dependent.** `Color.green` bridges to
///    `0.204, 0.780, 0.349` under aqua and `0.188, 0.820, 0.345` under
///    darkAqua, so whichever appearance was current when a settings file was
///    first written got frozen into it. Aqua is the value a headless process
///    resolves, so it is the one taken here.
///
/// A stored colour has always been a fixed `RGBA` — the widgets never
/// re-resolve it — so pinning the defaults changes nothing a user can see
/// beyond making them the same on every machine.
extension RGBA {
    static let systemGreen = RGBA(red: 0.20392151176929474, green: 0.78039216995239258, blue: 0.34901958703994751)
    static let systemOrange = RGBA(red: 1, green: 0.55294120311737061, blue: 0.15686275064945221)
    static let systemBlue = RGBA(red: 0, green: 0.53333336114883423, blue: 1)
    static let systemCyan = RGBA(red: 0, green: 0.75294119119644165, blue: 0.90980386734008789)
    static let systemTeal = RGBA(red: 0, green: 0.76470589637756348, blue: 0.81568628549575806)
    static let systemRed = RGBA(red: 1, green: 0.21960783004760742, blue: 0.23529410362243652)
    static let systemGray = RGBA(red: 0.55686277151107788, green: 0.55686277151107788, blue: 0.57647061347961426)
    static let systemYellow = RGBA(red: 1, green: 0.80000001192092896, blue: 0)
    static let systemPurple = RGBA(red: 0.79607844352722168, green: 0.18823529779911041, blue: 0.87843137979507446)
    static let systemPink = RGBA(red: 1, green: 0.17647059261798859, blue: 0.33333331346511841)
    static let systemMint = RGBA(red: 0, green: 0.78431367874145508, blue: 0.70196080207824707)
    static let systemIndigo = RGBA(red: 0.38039213418960571, green: 0.33333331346511841, blue: 0.96078437566757202)

    /// Every entry, for the tests that check the palette as a whole.
    static let palette: [RGBA] = [
        systemGreen, systemOrange, systemBlue, systemCyan, systemTeal, systemRed,
        systemGray, systemYellow, systemPurple, systemPink, systemMint, systemIndigo,
    ]
}

// MARK: - Settings

struct DeckSettings: Codable, Equatable {
    var livebox = LiveBoxSettings()
    var openbox = OpenBoxSettings()
    var netbox = NetBoxSettings()
    var batbox = BatBoxSettings()
    var gitbox = GitBoxSettings()
    var devbox = DevBoxSettings()
    var clipbox = ClipBoxSettings()
    var weatherbox = WeatherBoxSettings()
    var clockbox = ClockBoxSettings()
    var shipbox = ShipBoxSettings()
    var taskbox = TaskBoxSettings()
    var calbox = CalBoxSettings()
    var prbox = PRBoxSettings()
    var marketbox = MarketBoxSettings()
    /// Every credential the user has configured. Widgets reference these by id
    /// rather than each owning a token of its own.
    var credentials = CredentialsSettings()
    var agentAtLogin = true
    /// Whether the one-time "your identifier changed, re-add your widgets"
    /// notice has been dismissed. Written into the **new** container, so it
    /// cannot loop — a flag left behind in the old one would be re-read as
    /// false on every launch.
    var didShowRenameNotice = false
    /// When Deck first knew a registration for its background agents existed —
    /// either because it registered them, or because it found them already
    /// `.enabled` and adopted the moment it noticed.
    ///
    /// The grace-period clock for `AgentLivenessPolicy`, and nothing else: it
    /// is a diagnostic timestamp, not a preference. It is never shown, and
    /// losing it costs exactly one grace window. Without it, "registered ages
    /// ago and never ran" is indistinguishable from "registered a second ago
    /// and hasn't run yet" — and the first of those is the state the bundle
    /// rename puts every user into.
    var agentsRegisteredAt: Date?

    init() {}

    /// Tolerant decode at the container level, not just inside each section.
    ///
    /// The sub-structs were made tolerant in `settings-schema-migration`, but
    /// `DeckSettings` itself stayed on the synthesized decoder, which throws
    /// `keyNotFound` for any absent section. Combined with `load()`'s
    /// `?? DeckSettings()` fallback that means adding a widget silently resets
    /// EVERY setting — colors, tokens, repo paths — for anyone whose
    /// `settings.json` predates it. Adding `taskbox` is exactly that case, so
    /// a missing section now falls back to its defaults and leaves the rest of
    /// the user's configuration intact.
    /// Explicit rather than synthesized: the decoder needs a second key set
    /// for the retired `homebox` section, and putting that legacy case in the
    /// main enum would make the synthesized *encoder* try to write a property
    /// that no longer exists.
    enum CodingKeys: String, CodingKey {
        case livebox, openbox, netbox, batbox, gitbox, devbox, clipbox
        case weatherbox, clockbox, shipbox, taskbox, calbox, prbox
        case marketbox, credentials, agentAtLogin, didShowRenameNotice
        case agentsRegisteredAt
    }

    /// Decode-only. See `LegacyHomeBoxSettings`.
    private enum LegacyCodingKeys: String, CodingKey {
        case homebox
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        livebox = try c.decodeIfPresent(LiveBoxSettings.self, forKey: .livebox) ?? LiveBoxSettings()
        openbox = try c.decodeIfPresent(OpenBoxSettings.self, forKey: .openbox) ?? OpenBoxSettings()
        netbox = try c.decodeIfPresent(NetBoxSettings.self, forKey: .netbox) ?? NetBoxSettings()
        batbox = try c.decodeIfPresent(BatBoxSettings.self, forKey: .batbox) ?? BatBoxSettings()
        gitbox = try c.decodeIfPresent(GitBoxSettings.self, forKey: .gitbox) ?? GitBoxSettings()
        devbox = try c.decodeIfPresent(DevBoxSettings.self, forKey: .devbox) ?? DevBoxSettings()
        clipbox = try c.decodeIfPresent(ClipBoxSettings.self, forKey: .clipbox) ?? ClipBoxSettings()
        // `homebox` split into `weatherbox` + `clockbox`. A pre-split file has
        // neither new key, so both fall back to the legacy blob rather than
        // silently resetting the user's location, units and zones.
        let legacy = try? decoder.container(keyedBy: LegacyCodingKeys.self)
        let legacyHome = try? legacy?.decodeIfPresent(LegacyHomeBoxSettings.self, forKey: .homebox)
        weatherbox = try c.decodeIfPresent(WeatherBoxSettings.self, forKey: .weatherbox)
            ?? (legacyHome.flatMap { $0 }).map {
                WeatherBoxSettings(
                    location: $0.location,
                    unitsFahrenheit: $0.unitsFahrenheit,
                    showForecast: $0.showForecast
                )
            }
            ?? WeatherBoxSettings()
        clockbox = try c.decodeIfPresent(ClockBoxSettings.self, forKey: .clockbox)
            ?? (legacyHome.flatMap { $0 }).map { ClockBoxSettings(cityIDs: $0.timezoneIDs) }
            ?? ClockBoxSettings()
        shipbox = try c.decodeIfPresent(ShipBoxSettings.self, forKey: .shipbox) ?? ShipBoxSettings()
        taskbox = try c.decodeIfPresent(TaskBoxSettings.self, forKey: .taskbox) ?? TaskBoxSettings()
        calbox = try c.decodeIfPresent(CalBoxSettings.self, forKey: .calbox) ?? CalBoxSettings()
        prbox = try c.decodeIfPresent(PRBoxSettings.self, forKey: .prbox) ?? PRBoxSettings()
        marketbox = try c.decodeIfPresent(MarketBoxSettings.self, forKey: .marketbox) ?? MarketBoxSettings()
        credentials = try c.decodeIfPresent(CredentialsSettings.self, forKey: .credentials) ?? CredentialsSettings()
        agentAtLogin = try c.decodeIfPresent(Bool.self, forKey: .agentAtLogin) ?? true
        didShowRenameNotice = try c.decodeIfPresent(Bool.self, forKey: .didShowRenameNotice) ?? false
        agentsRegisteredAt = try c.decodeIfPresent(Date.self, forKey: .agentsRegisteredAt)
    }

    /// Settings live inside the widget extension's sandbox container so both
    /// the (unsandboxed) host app and the sandboxed extension can use them.
    /// NOTE: inside the sandbox, homeDirectoryForCurrentUser already points at
    /// the container (…/Containers/<DeckBundle.widgetsID>/Data), so the two
    /// resolve to the same absolute path.
    static var containerDirectory: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let isSandboxed = ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil
        if isSandboxed {
            return home.appendingPathComponent("Library/Application Support/Deck", isDirectory: true)
        }
        return home.appendingPathComponent(
            "Library/Containers/\(DeckBundle.widgetsID)/Data/Library/Application Support/Deck",
            isDirectory: true
        )
    }

    static var fileURL: URL {
        containerDirectory.appendingPathComponent("settings.json")
    }

    static func load() -> DeckSettings {
        guard let data = try? Data(contentsOf: Self.fileURL) else { return DeckSettings() }
        return (try? JSONDecoder().decode(DeckSettings.self, from: data)) ?? DeckSettings()
    }

    /// Tightens an existing `settings.json` that predates Deck restricting the
    /// mode — a file written at 0644 keeps that mode until it is rewritten.
    /// Idempotent and cheap; the host app calls it once at launch.
    static func tightenPermissions() {
        try? FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: 0o600)],
            ofItemAtPath: fileURL.path
        )
    }

    func save() {
        // The five credentials live in the keychain (`DeckKeychain`), never in
        // this file. `encode(to:)` is deliberately left symmetric — the decode
        // regression tests pin it — so the scrub happens here, at the file
        // boundary, on a copy.
        guard let data = try? JSONEncoder().encode(scrubbedOfSecrets()) else { return }
        // 0o600 still: the file carries repo paths, an org and project name and
        // a server URL. Secrets are gone, but this is nobody else's business.
        _ = AtomicFile.write(data, to: Self.fileURL, posixPermissions: 0o600)
    }

    // MARK: - Secrets

    /// A copy with the five keychain-backed credentials blanked.
    func scrubbedOfSecrets() -> DeckSettings {
        var copy = self
        copy.openbox.token = ""
        copy.shipbox.token = ""
        copy.taskbox.token = ""
        copy.prbox.github.token = ""
        copy.prbox.azure.token = ""
        // R4: the five above are a fixed list a human can audit; the accounts
        // are not. `CredentialAccount.encode(to:)` already omits the token,
        // so this is the second of two independent guarantees.
        for index in copy.credentials.accounts.indices {
            copy.credentials.accounts[index].token = ""
        }
        return copy
    }

    /// Fills the five credential fields from a set of keychain reads and
    /// returns the keys that **failed** — which is not the same as being
    /// unset, and callers must not treat it as such.
    ///
    /// Two rules, both load-bearing:
    ///
    /// - `.found` overwrites. Nothing else does.
    /// - `.absent` and `.failed` leave whatever was decoded from the file
    ///   **exactly as it was**. Before the migration has run, that file value
    ///   is the user's real token, and it is what keeps a Deck that was
    ///   upgraded but never opened working — `DeckAgent` reads settings and
    ///   never writes them, so it can run on an unmigrated file indefinitely.
    ///   Blanking here would wipe four widgets' credentials at the first tick.
    @discardableResult
    mutating func hydrate(from reads: [DeckSecret: SecretRead]) -> Set<DeckSecret> {
        var failed: Set<DeckSecret> = []
        for secret in DeckSecret.allCases {
            switch reads[secret] {
            case .found(let value):
                setSecret(value, for: secret)
            case .failed:
                failed.insert(secret)
            case .absent, nil:
                break
            }
        }
        return failed
    }

    /// `hydrate(from:)` against the real keychain. Host-side only — the widget
    /// extension never calls this and needs no keychain access.
    @discardableResult
    mutating func hydrateFromKeychain() -> Set<DeckSecret> {
        hydrate(from: DeckKeychain.readAll())
    }

    mutating func setSecret(_ value: String, for secret: DeckSecret) {
        switch secret {
        case .openboxToken: openbox.token = value
        case .shipboxToken: shipbox.token = value
        case .taskboxToken: taskbox.token = value
        case .prboxGitHubToken: prbox.github.token = value
        case .prboxAzureToken: prbox.azure.token = value
        }
    }

    // MARK: - Accounts

    /// The account id a slot is pointed at, or `nil` when it is unset.
    func accountID(for slot: CredentialSlot) -> String? {
        switch slot {
        case .openbox: return openbox.accountID
        case .shipbox: return shipbox.accountID
        case .taskbox: return taskbox.accountID
        case .prboxGitHub: return prbox.github.accountID
        case .prboxAzure: return prbox.azure.accountID
        }
    }

    mutating func setAccountID(_ id: String?, for slot: CredentialSlot) {
        switch slot {
        case .openbox: openbox.accountID = id
        case .shipbox: shipbox.accountID = id
        case .taskbox: taskbox.accountID = id
        case .prboxGitHub: prbox.github.accountID = id
        case .prboxAzure: prbox.azure.accountID = id
        }
    }

    /// The account a slot resolves to, or `nil` when it is unset, **dangles**
    /// (the account was deleted behind it) or names an account of the wrong
    /// kind. All three read as "not configured" — never as an error.
    func account(for slot: CredentialSlot) -> CredentialAccount? {
        guard let id = accountID(for: slot) else { return nil }
        guard let account = credentials.accounts.first(where: { $0.id == id }) else { return nil }
        return account.kind == slot.kind ? account : nil
    }

    /// Which widgets would stop working if this account went away. Drives the
    /// delete confirmation, which names them rather than deleting silently.
    func slots(using accountID: String) -> [CredentialSlot] {
        CredentialSlot.allCases.filter { self.accountID(for: $0) == accountID }
    }

    /// Fills every account's token from a set of keychain reads and returns the
    /// ids that **failed** — which is not the same as being unset.
    ///
    /// The two rules are the legacy `hydrate(from:)`'s, unchanged: `.found`
    /// overwrites, and nothing else does. Blanking on a failure would wipe a
    /// working credential the moment the keychain hiccups.
    @discardableResult
    mutating func hydrateAccounts(from reads: [String: SecretRead]) -> Set<String> {
        var failed: Set<String> = []
        for index in credentials.accounts.indices {
            switch reads[credentials.accounts[index].id] {
            case .found(let value):
                credentials.accounts[index].token = value
            case .failed:
                failed.insert(credentials.accounts[index].id)
            case .absent, nil:
                break
            }
        }
        return failed
    }

    /// `hydrateAccounts(from:)` against the real keychain. Host-side only — the
    /// widget extension never calls this and needs no keychain access.
    @discardableResult
    mutating func hydrateAccountsFromKeychain() -> Set<String> {
        hydrateAccounts(from: DeckKeychain.readAll(accountIDs: credentials.accounts.map(\.id)))
    }

    /// The current in-memory value of one credential, for the migration.
    func secretValue(_ secret: DeckSecret) -> String {
        switch secret {
        case .openboxToken: return openbox.token
        case .shipboxToken: return shipbox.token
        case .taskboxToken: return taskbox.token
        case .prboxGitHubToken: return prbox.github.token
        case .prboxAzureToken: return prbox.azure.token
        }
    }
}

struct LiveBoxSettings: Codable, Equatable {
    var showChart = true
    var showCPU = true
    var showMEM = true
    var showDisk = true
    var showPerVolumeDisk = true
    /// Thermal pressure row — opt-in so existing widgets don't gain a row.
    var showThermal = false
    var showProcesses = true
    var showPerCoreCores = false
    var processCount = 3
    /// Seconds between widget render ticks and fast process-snapshot samples.
    var processRefreshInterval = 15
    var cpuColor = RGBA.systemGreen
    var memColor = RGBA.systemCyan
    var diskColor = RGBA.systemOrange
    var showThresholdColors = true
    var cpuWarnThreshold = 80
    var cpuAlarmThreshold = 90
    var memWarnThreshold = 80
    var memAlarmThreshold = 90
    var diskWarnThreshold = 80
    var diskAlarmThreshold = 90

    /// Tolerant decode: missing keys keep the defaults instead of throwing
    /// (the synthesized decoder throws, which would reset every setting via
    /// `DeckSettings.load()`'s fallback when old settings.json files lack
    /// newly added keys).
    init() {}

    /// Decode-only legacy keys (`warnThreshold`/`alarmThreshold`): read from the
    /// container for the migration fallback, never stored, so the synthesized
    /// encoder writes only the six per-metric keys (one-way migration).
    enum CodingKeys: String, CodingKey {
        case showChart, showCPU, showMEM, showDisk, showPerVolumeDisk, showThermal
        case showProcesses, showPerCoreCores, processCount, processRefreshInterval
        case cpuColor, memColor, diskColor, showThresholdColors
        case cpuWarnThreshold, cpuAlarmThreshold, memWarnThreshold, memAlarmThreshold
        case diskWarnThreshold, diskAlarmThreshold
        case warnThreshold, alarmThreshold
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        showChart = try c.decodeIfPresent(Bool.self, forKey: .showChart) ?? true
        showCPU = try c.decodeIfPresent(Bool.self, forKey: .showCPU) ?? true
        showMEM = try c.decodeIfPresent(Bool.self, forKey: .showMEM) ?? true
        showDisk = try c.decodeIfPresent(Bool.self, forKey: .showDisk) ?? true
        showPerVolumeDisk = try c.decodeIfPresent(Bool.self, forKey: .showPerVolumeDisk) ?? true
        showThermal = try c.decodeIfPresent(Bool.self, forKey: .showThermal) ?? false
        showProcesses = try c.decodeIfPresent(Bool.self, forKey: .showProcesses) ?? true
        showPerCoreCores = try c.decodeIfPresent(Bool.self, forKey: .showPerCoreCores) ?? false
        processCount = try c.decodeIfPresent(Int.self, forKey: .processCount) ?? 3
        processRefreshInterval = try c.decodeIfPresent(Int.self, forKey: .processRefreshInterval) ?? 15
        cpuColor = try c.decodeIfPresent(RGBA.self, forKey: .cpuColor) ?? RGBA.systemGreen
        memColor = try c.decodeIfPresent(RGBA.self, forKey: .memColor) ?? RGBA.systemCyan
        diskColor = try c.decodeIfPresent(RGBA.self, forKey: .diskColor) ?? RGBA.systemOrange
        showThresholdColors = try c.decodeIfPresent(Bool.self, forKey: .showThresholdColors) ?? true
        // Per-metric keys with a legacy-pair fallback (settings-schema migration,
        // ROADMAP.md:56): a per-metric key wins, else the old shared pair, else 80/90.
        cpuWarnThreshold = try c.decodeIfPresent(Int.self, forKey: .cpuWarnThreshold)
            ?? c.decodeIfPresent(Int.self, forKey: .warnThreshold) ?? 80
        cpuAlarmThreshold = try c.decodeIfPresent(Int.self, forKey: .cpuAlarmThreshold)
            ?? c.decodeIfPresent(Int.self, forKey: .alarmThreshold) ?? 90
        memWarnThreshold = try c.decodeIfPresent(Int.self, forKey: .memWarnThreshold)
            ?? c.decodeIfPresent(Int.self, forKey: .warnThreshold) ?? 80
        memAlarmThreshold = try c.decodeIfPresent(Int.self, forKey: .memAlarmThreshold)
            ?? c.decodeIfPresent(Int.self, forKey: .alarmThreshold) ?? 90
        diskWarnThreshold = try c.decodeIfPresent(Int.self, forKey: .diskWarnThreshold)
            ?? c.decodeIfPresent(Int.self, forKey: .warnThreshold) ?? 80
        diskAlarmThreshold = try c.decodeIfPresent(Int.self, forKey: .diskAlarmThreshold)
            ?? c.decodeIfPresent(Int.self, forKey: .alarmThreshold) ?? 90
    }

    /// Writes only the six per-metric keys — the legacy pair is decode-only, so
    /// this is a one-way settings-schema migration.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(showChart, forKey: .showChart)
        try c.encode(showCPU, forKey: .showCPU)
        try c.encode(showMEM, forKey: .showMEM)
        try c.encode(showDisk, forKey: .showDisk)
        try c.encode(showPerVolumeDisk, forKey: .showPerVolumeDisk)
        try c.encode(showThermal, forKey: .showThermal)
        try c.encode(showProcesses, forKey: .showProcesses)
        try c.encode(showPerCoreCores, forKey: .showPerCoreCores)
        try c.encode(processCount, forKey: .processCount)
        try c.encode(processRefreshInterval, forKey: .processRefreshInterval)
        try c.encode(cpuColor, forKey: .cpuColor)
        try c.encode(memColor, forKey: .memColor)
        try c.encode(diskColor, forKey: .diskColor)
        try c.encode(showThresholdColors, forKey: .showThresholdColors)
        try c.encode(cpuWarnThreshold, forKey: .cpuWarnThreshold)
        try c.encode(cpuAlarmThreshold, forKey: .cpuAlarmThreshold)
        try c.encode(memWarnThreshold, forKey: .memWarnThreshold)
        try c.encode(memAlarmThreshold, forKey: .memAlarmThreshold)
        try c.encode(diskWarnThreshold, forKey: .diskWarnThreshold)
        try c.encode(diskAlarmThreshold, forKey: .diskAlarmThreshold)
    }
}

struct OpenBoxSettings: Codable, Equatable {
    var token = ""
    /// The credential this widget uses, by `CredentialAccount.id`. `nil` means
    /// no account is selected, which reads as "not configured".
    var accountID: String?
    /// Non-empty → remote server mode (auto-switch); empty → local DB.
    var serverURL: String?
    var refreshInterval = 60
    var showChart = true
    var showCostChart = false
    var showModels = true
    var showTools = false
    var showSessions = false
    var toolCount = 3
    var modelCount = 3
    var sessionCount = 3
    var inputColor = RGBA.systemCyan
    var outputColor = RGBA.systemGreen
    var costColor = RGBA.systemOrange

    /// Tolerant decode: missing keys keep the defaults instead of throwing
    /// (the synthesized decoder throws, which would reset every setting via
    /// `DeckSettings.load()`'s fallback when old settings.json files lack
    /// newly added keys).
    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        token = try c.decodeIfPresent(String.self, forKey: .token) ?? ""
        accountID = try c.decodeIfPresent(String.self, forKey: .accountID)
        serverURL = try c.decodeIfPresent(String.self, forKey: .serverURL)
        refreshInterval = try c.decodeIfPresent(Int.self, forKey: .refreshInterval) ?? 60
        showChart = try c.decodeIfPresent(Bool.self, forKey: .showChart) ?? true
        showCostChart = try c.decodeIfPresent(Bool.self, forKey: .showCostChart) ?? false
        showModels = try c.decodeIfPresent(Bool.self, forKey: .showModels) ?? true
        showTools = try c.decodeIfPresent(Bool.self, forKey: .showTools) ?? false
        showSessions = try c.decodeIfPresent(Bool.self, forKey: .showSessions) ?? false
        toolCount = try c.decodeIfPresent(Int.self, forKey: .toolCount) ?? 3
        modelCount = try c.decodeIfPresent(Int.self, forKey: .modelCount) ?? 3
        sessionCount = try c.decodeIfPresent(Int.self, forKey: .sessionCount) ?? 3
        inputColor = try c.decodeIfPresent(RGBA.self, forKey: .inputColor) ?? RGBA.systemCyan
        outputColor = try c.decodeIfPresent(RGBA.self, forKey: .outputColor) ?? RGBA.systemGreen
        costColor = try c.decodeIfPresent(RGBA.self, forKey: .costColor) ?? RGBA.systemOrange
    }
}

struct NetBoxSettings: Codable, Equatable {
    var showChart = true
    var showInterfaces = true
    var interfaceCount = 3
    /// Non-empty → pinned to one interface; nil → auto "most active".
    var pinnedInterface: String?
    var upColor = RGBA.systemGreen
    var downColor = RGBA.systemCyan
    var showThresholdColors = true
    /// MB/s (decimal, ×1,000,000 — matches NetBoxFormatters).
    var warnThreshold = 50
    var alarmThreshold = 100

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        showChart = try c.decodeIfPresent(Bool.self, forKey: .showChart) ?? true
        showInterfaces = try c.decodeIfPresent(Bool.self, forKey: .showInterfaces) ?? true
        interfaceCount = try c.decodeIfPresent(Int.self, forKey: .interfaceCount) ?? 3
        pinnedInterface = try c.decodeIfPresent(String.self, forKey: .pinnedInterface)
        upColor = try c.decodeIfPresent(RGBA.self, forKey: .upColor) ?? RGBA.systemGreen
        downColor = try c.decodeIfPresent(RGBA.self, forKey: .downColor) ?? RGBA.systemCyan
        showThresholdColors = try c.decodeIfPresent(Bool.self, forKey: .showThresholdColors) ?? true
        // Floor at 1 so a hand-edited 0 can never make every rate an alarm.
        warnThreshold = max(1, try c.decodeIfPresent(Int.self, forKey: .warnThreshold) ?? 50)
        alarmThreshold = max(1, try c.decodeIfPresent(Int.self, forKey: .alarmThreshold) ?? 100)
    }
}

struct BatBoxSettings: Codable, Equatable {
    var showChart = true
    var showStatus = true
    var levelColor = RGBA.systemGreen
    var showAccessories = true
    var accessoryCount = 4

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        showChart = try c.decodeIfPresent(Bool.self, forKey: .showChart) ?? true
        showStatus = try c.decodeIfPresent(Bool.self, forKey: .showStatus) ?? true
        levelColor = try c.decodeIfPresent(RGBA.self, forKey: .levelColor) ?? RGBA.systemGreen
        showAccessories = try c.decodeIfPresent(Bool.self, forKey: .showAccessories) ?? true
        accessoryCount = try c.decodeIfPresent(Int.self, forKey: .accessoryCount) ?? 4
    }
}

struct GitBoxSettings: Codable, Equatable {
    var showChart = true
    var showRepos = true
    var repoCount = 5
    var scanDepth = 3
    var repoPaths: [String] = []
    var barColor = RGBA.systemBlue
    var todayColor = RGBA.systemOrange

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        showChart = try c.decodeIfPresent(Bool.self, forKey: .showChart) ?? true
        showRepos = try c.decodeIfPresent(Bool.self, forKey: .showRepos) ?? true
        repoCount = try c.decodeIfPresent(Int.self, forKey: .repoCount) ?? 5
        scanDepth = try c.decodeIfPresent(Int.self, forKey: .scanDepth) ?? 3
        repoPaths = try c.decodeIfPresent([String].self, forKey: .repoPaths) ?? []
        barColor = try c.decodeIfPresent(RGBA.self, forKey: .barColor) ?? RGBA.systemBlue
        todayColor = try c.decodeIfPresent(RGBA.self, forKey: .todayColor) ?? RGBA.systemOrange
    }
}

struct DevBoxSettings: Codable, Equatable {
    var showPorts = true
    var showContainers = true
    var portCount = 5
    var containerCount = 5
    var portColor = RGBA.systemTeal
    var containerColor = RGBA.systemMint

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        showPorts = try c.decodeIfPresent(Bool.self, forKey: .showPorts) ?? true
        showContainers = try c.decodeIfPresent(Bool.self, forKey: .showContainers) ?? true
        portCount = try c.decodeIfPresent(Int.self, forKey: .portCount) ?? 5
        containerCount = try c.decodeIfPresent(Int.self, forKey: .containerCount) ?? 5
        portColor = try c.decodeIfPresent(RGBA.self, forKey: .portColor) ?? RGBA.systemTeal
        containerColor = try c.decodeIfPresent(RGBA.self, forKey: .containerColor) ?? RGBA.systemMint
    }
}

struct ClipBoxSettings: Codable, Equatable {
    var showList = true
    var historyCount = 5
    var textColor = RGBA.systemIndigo
    var imageColor = RGBA.systemPink
    var fileColor = RGBA.systemBlue
    var otherColor = RGBA.systemGray

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        showList = try c.decodeIfPresent(Bool.self, forKey: .showList) ?? true
        historyCount = try c.decodeIfPresent(Int.self, forKey: .historyCount) ?? 5
        textColor = try c.decodeIfPresent(RGBA.self, forKey: .textColor) ?? RGBA.systemIndigo
        imageColor = try c.decodeIfPresent(RGBA.self, forKey: .imageColor) ?? RGBA.systemPink
        fileColor = try c.decodeIfPresent(RGBA.self, forKey: .fileColor) ?? RGBA.systemBlue
        otherColor = try c.decodeIfPresent(RGBA.self, forKey: .otherColor) ?? RGBA.systemGray
    }
}

struct WeatherBoxSettings: Codable, Equatable {
    var location = ""
    var unitsFahrenheit = false
    var showForecast = true

    init() {}

    init(location: String, unitsFahrenheit: Bool, showForecast: Bool) {
        self.location = location
        self.unitsFahrenheit = unitsFahrenheit
        self.showForecast = showForecast
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        location = try c.decodeIfPresent(String.self, forKey: .location) ?? ""
        unitsFahrenheit = try c.decodeIfPresent(Bool.self, forKey: .unitsFahrenheit) ?? false
        showForecast = try c.decodeIfPresent(Bool.self, forKey: .showForecast) ?? true
    }
}

struct ClockBoxSettings: Codable, Equatable {
    /// IANA identifiers, plus the `ClockBoxCore.localID` sentinel. Capped at
    /// `ClockBoxCore.maxCities` on decode so a hand-edited file cannot push
    /// more faces into the widget than it can lay out.
    var cityIDs = [ClockBoxCore.localID, "UTC"]
    /// Which city the small face shows. Empty → auto (first non-local).
    var mainCityID = ""
    var showRelativeDay = true
    var showOffset = true
    var timeColor = RGBA.systemTeal

    init() {}

    init(cityIDs: [String]) {
        self.cityIDs = Array(cityIDs.prefix(ClockBoxCore.maxCities))
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let decoded = try c.decodeIfPresent([String].self, forKey: .cityIDs)
            ?? [ClockBoxCore.localID, "UTC"]
        cityIDs = Array(decoded.prefix(ClockBoxCore.maxCities))
        mainCityID = try c.decodeIfPresent(String.self, forKey: .mainCityID) ?? ""
        showRelativeDay = try c.decodeIfPresent(Bool.self, forKey: .showRelativeDay) ?? true
        showOffset = try c.decodeIfPresent(Bool.self, forKey: .showOffset) ?? true
        timeColor = try c.decodeIfPresent(RGBA.self, forKey: .timeColor) ?? RGBA.systemTeal
    }
}

/// Decode-only shape of the retired `homebox` section, used once to carry a
/// pre-split `settings.json` across to `weatherbox` + `clockbox`. Never
/// encoded — the migration is one-way.
private struct LegacyHomeBoxSettings: Decodable {
    var location = ""
    var unitsFahrenheit = false
    var timezoneIDs = [ClockBoxCore.localID, "UTC"]
    var showForecast = true

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        location = try c.decodeIfPresent(String.self, forKey: .location) ?? ""
        unitsFahrenheit = try c.decodeIfPresent(Bool.self, forKey: .unitsFahrenheit) ?? false
        timezoneIDs = try c.decodeIfPresent([String].self, forKey: .timezoneIDs)
            ?? [ClockBoxCore.localID, "UTC"]
        showForecast = try c.decodeIfPresent(Bool.self, forKey: .showForecast) ?? true
    }

    enum CodingKeys: String, CodingKey {
        case location, unitsFahrenheit, timezoneIDs, showForecast
    }
}

/// How ShipBox decides which repos to watch.
enum ShipBoxRepoMode: String, Codable, Equatable, CaseIterable {
    /// The repos you pushed to most recently that have any Actions runs.
    /// Discovered every tick; the set changes as you push.
    case dynamic
    /// Exactly the repos picked in settings.
    case staticList = "static"
}

struct ShipBoxSettings: Codable, Equatable {
    /// Auto-discovery or explicit picks. Dynamic is the default because it
    /// needs nothing but a token.
    var repoMode = ShipBoxRepoMode.dynamic
    /// "owner/repo" entries in display order, used by `.staticList` only.
    /// Empty in static mode → agent skips the fetch.
    var repos: [String] = []
    /// How many repos `.dynamic` watches. Bounded by `maxRepoCount` so the
    /// fan-out stays inside one 60s tick.
    var maxRepoCount = 3
    /// GitHub personal access token — required; no default is ever sent.
    var token = ""
    /// The credential this widget uses, by `CredentialAccount.id`. `nil` means
    /// no account is selected, which reads as "not configured".
    var accountID: String?
    var showList = true
    var runCount = 4
    /// Round-robin interleave across repos so a busy repo's history cannot
    /// hide a quiet repo's latest run (ShipBoxMerge.fairMerge). Read by the
    /// agent at merge time; the widget extension never reads it.
    var fairShare = true
    var queuedColor = RGBA.systemOrange
    var runningColor = RGBA.systemYellow
    var successColor = RGBA.systemGreen
    var failureColor = RGBA.systemRed

    /// Both the static slot count and the dynamic ceiling. Five repos is the
    /// most the fan-out can fetch and the face can name.
    static let maxRepoCount = 5

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // `repo` was the single-target shape this widget shipped with. A
        // non-empty legacy value migrates to a one-entry static list: the user
        // chose that repo, and dropping them into auto-discovery would replace
        // it with whatever they happened to push to most recently.
        let legacy = try c.decodeIfPresent(String.self, forKey: .legacyRepo)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let decoded = try c.decodeIfPresent([String].self, forKey: .repos) {
            repos = Self.normalized(decoded)
        } else if let legacy, !legacy.isEmpty {
            repos = Self.normalized([legacy])
        } else {
            repos = []
        }
        // An unknown mode (written by a newer build) reads as dynamic rather
        // than throwing — a throw here resets every other widget's settings.
        if let raw = try c.decodeIfPresent(String.self, forKey: .repoMode) {
            repoMode = ShipBoxRepoMode(rawValue: raw) ?? .dynamic
        } else if let legacy, !legacy.isEmpty {
            repoMode = .staticList
        } else {
            repoMode = .dynamic
        }
        maxRepoCount = min(max(try c.decodeIfPresent(Int.self, forKey: .maxRepoCount) ?? 3, 1), Self.maxRepoCount)
        token = try c.decodeIfPresent(String.self, forKey: .token) ?? ""
        accountID = try c.decodeIfPresent(String.self, forKey: .accountID)
        showList = try c.decodeIfPresent(Bool.self, forKey: .showList) ?? true
        runCount = try c.decodeIfPresent(Int.self, forKey: .runCount) ?? 4
        fairShare = try c.decodeIfPresent(Bool.self, forKey: .fairShare) ?? true
        queuedColor = try c.decodeIfPresent(RGBA.self, forKey: .queuedColor) ?? RGBA.systemOrange
        runningColor = try c.decodeIfPresent(RGBA.self, forKey: .runningColor) ?? RGBA.systemYellow
        successColor = try c.decodeIfPresent(RGBA.self, forKey: .successColor) ?? RGBA.systemGreen
        failureColor = try c.decodeIfPresent(RGBA.self, forKey: .failureColor) ?? RGBA.systemRed
    }

    /// Writes only the current shape: the legacy `repo` key is read on the way
    /// in and dropped on the way out, so a file migrates once and stays clean.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(repoMode, forKey: .repoMode)
        try c.encode(repos, forKey: .repos)
        try c.encode(maxRepoCount, forKey: .maxRepoCount)
        try c.encode(token, forKey: .token)
        try c.encodeIfPresent(accountID, forKey: .accountID)
        try c.encode(showList, forKey: .showList)
        try c.encode(runCount, forKey: .runCount)
        try c.encode(fairShare, forKey: .fairShare)
        try c.encode(queuedColor, forKey: .queuedColor)
        try c.encode(runningColor, forKey: .runningColor)
        try c.encode(successColor, forKey: .successColor)
        try c.encode(failureColor, forKey: .failureColor)
    }

    /// Trimmed, empties dropped, capped at `maxRepoCount`, deduped
    /// case-insensitively — GitHub treats `A/B` and `a/b` as one repo, so
    /// keeping both would double the fetch and duplicate every row. The first
    /// spelling wins, because it is the one the user typed or picked.
    static func normalized(_ repos: [String]) -> [String] {
        var kept: [String] = []
        var seen: Set<String> = []
        for repo in repos {
            let trimmed = repo.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seen.insert(trimmed.lowercased()).inserted else { continue }
            kept.append(trimmed)
            if kept.count == maxRepoCount { break }
        }
        return kept
    }

    private enum CodingKeys: String, CodingKey {
        case repoMode, repos, maxRepoCount, token, accountID, showList, runCount, fairShare
        case queuedColor, runningColor, successColor, failureColor
        case legacyRepo = "repo"
    }
}

struct TaskBoxSettings: Codable, Equatable {
    /// Azure DevOps organization — a bare name or a full dev.azure.com URL.
    /// Empty → agent skips the fetch.
    var organization = ""
    /// Project within the organization. Empty → agent skips the fetch. The
    /// query is scoped to it, so items in the org's other projects stay out.
    var project = ""
    /// Personal access token — required; no default is ever sent. A read-only
    /// Work Items (Read) scope is enough.
    var token = ""
    /// The credential this widget uses, by `CredentialAccount.id`. `nil` means
    /// no account is selected, which reads as "not configured".
    var accountID: String?
    /// The lane legend under the header.
    var showLegend = true
    var showList = true
    /// Tag each row with the Azure project it came from. Off by default: with
    /// one project it would repeat the header on every row, and the row already
    /// carries a type, a title and a state.
    var showProject = false
    var taskCount = 5
    /// Which raw Azure DevOps states feed which lane. Editable because process
    /// templates get customised and board columns get renamed.
    var stateMapping = TaskStateMapping()
    var todoColor = RGBA.systemBlue
    var inProgressColor = RGBA.systemOrange
    var testingColor = RGBA.systemPurple
    var doneColor = RGBA.systemGreen
    var otherColor = RGBA.systemGray

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        organization = try c.decodeIfPresent(String.self, forKey: .organization) ?? ""
        project = try c.decodeIfPresent(String.self, forKey: .project) ?? ""
        token = try c.decodeIfPresent(String.self, forKey: .token) ?? ""
        accountID = try c.decodeIfPresent(String.self, forKey: .accountID)
        showLegend = try c.decodeIfPresent(Bool.self, forKey: .showLegend) ?? true
        showList = try c.decodeIfPresent(Bool.self, forKey: .showList) ?? true
        showProject = try c.decodeIfPresent(Bool.self, forKey: .showProject) ?? false
        taskCount = try c.decodeIfPresent(Int.self, forKey: .taskCount) ?? 5
        stateMapping = try c.decodeIfPresent(TaskStateMapping.self, forKey: .stateMapping) ?? TaskStateMapping()
        todoColor = try c.decodeIfPresent(RGBA.self, forKey: .todoColor) ?? RGBA.systemBlue
        inProgressColor = try c.decodeIfPresent(RGBA.self, forKey: .inProgressColor) ?? RGBA.systemOrange
        testingColor = try c.decodeIfPresent(RGBA.self, forKey: .testingColor) ?? RGBA.systemPurple
        doneColor = try c.decodeIfPresent(RGBA.self, forKey: .doneColor) ?? RGBA.systemGreen
        otherColor = try c.decodeIfPresent(RGBA.self, forKey: .otherColor) ?? RGBA.systemGray
    }

    /// Lane → configured dot colour, in one place so the legend and the rows
    /// can never disagree.
    func color(for lane: TaskLane) -> RGBA {
        switch lane {
        case .todo: todoColor
        case .inProgress: inProgressColor
        case .testing: testingColor
        case .done: doneColor
        case .other: otherColor
        }
    }
}

struct CalBoxSettings: Codable, Equatable {
    /// `EKCalendar.calendarIdentifier`s to read — empty → agent skips the read.
    var calendarIDs: [String] = []
    /// Set once the defaults have been applied. After that the user's list is
    /// authoritative: nothing is ever enabled behind their back, so a calendar
    /// added to macOS later shows up in settings unticked and waits.
    var hasChosenCalendars = false
    /// All-day events, shown at the top of TODAY.
    var showAllDay = true
    var showToday = true
    var showTomorrow = true
    /// Rows per section on the large face. Smaller faces cap lower — past that
    /// the rows are clipped by the frame rather than by the setting.
    var todayCount = 6
    var tomorrowCount = 4
    /// Off → every dot uses `accentColor` instead of the calendar's own colour.
    var useCalendarColors = true
    var accentColor = RGBA.systemBlue

    static let maxCount = 10

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        calendarIDs = try c.decodeIfPresent([String].self, forKey: .calendarIDs) ?? []
        hasChosenCalendars = try c.decodeIfPresent(Bool.self, forKey: .hasChosenCalendars) ?? false
        showAllDay = try c.decodeIfPresent(Bool.self, forKey: .showAllDay) ?? true
        // `showAgenda` and `eventCount` were the single-list shape this widget
        // shipped with before the face split into TODAY and TOMORROW. Carry
        // them over rather than silently resetting someone's choice.
        let legacyShowAgenda = try c.decodeIfPresent(Bool.self, forKey: .legacyShowAgenda)
        let legacyEventCount = try c.decodeIfPresent(Int.self, forKey: .legacyEventCount)
        showToday = try c.decodeIfPresent(Bool.self, forKey: .showToday) ?? legacyShowAgenda ?? true
        showTomorrow = try c.decodeIfPresent(Bool.self, forKey: .showTomorrow) ?? true
        todayCount = try c.decodeIfPresent(Int.self, forKey: .todayCount) ?? legacyEventCount ?? 6
        tomorrowCount = try c.decodeIfPresent(Int.self, forKey: .tomorrowCount) ?? 4
        useCalendarColors = try c.decodeIfPresent(Bool.self, forKey: .useCalendarColors) ?? true
        accentColor = try c.decodeIfPresent(RGBA.self, forKey: .accentColor) ?? RGBA.systemBlue
        // A hand-edited or older file must not produce a face that clips.
        todayCount = min(max(todayCount, 1), Self.maxCount)
        tomorrowCount = min(max(tomorrowCount, 1), Self.maxCount)
    }

    /// Writes only the current shape: the legacy keys are read on the way in
    /// (see `init(from:)`) and dropped on the way out, so a file migrates once
    /// and then stays clean.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(calendarIDs, forKey: .calendarIDs)
        try c.encode(hasChosenCalendars, forKey: .hasChosenCalendars)
        try c.encode(showAllDay, forKey: .showAllDay)
        try c.encode(showToday, forKey: .showToday)
        try c.encode(showTomorrow, forKey: .showTomorrow)
        try c.encode(todayCount, forKey: .todayCount)
        try c.encode(tomorrowCount, forKey: .tomorrowCount)
        try c.encode(useCalendarColors, forKey: .useCalendarColors)
        try c.encode(accentColor, forKey: .accentColor)
    }

    private enum CodingKeys: String, CodingKey {
        case calendarIDs, hasChosenCalendars, showAllDay
        case showToday, showTomorrow, todayCount, tomorrowCount
        case useCalendarColors, accentColor
        case legacyShowAgenda = "showAgenda"
        case legacyEventCount = "eventCount"
    }
}

// MARK: - ColorPicker binding helper
extension Binding where Value == RGBA {
    var color: Binding<Color> {
        Binding<Color>(
            get: { wrappedValue.color },
            // SwiftUI runs a Binding's setter on the main thread; the
            // assumption is stated rather than assumed so the @MainActor on
            // `RGBA.init(_:)` keeps protecting every other caller.
            set: { newValue in
                MainActor.assumeIsolated { wrappedValue = RGBA(newValue) }
            }
        )
    }
}

// MARK: - PRBox
//
// PRBox is the first widget to talk to two providers, so its settings are two
// sub-sections plus the shared presentation. Each provider carries its own
// credentials rather than borrowing ShipBox's GitHub token or TaskBox's Azure
// PAT: every Deck widget owns its settings, and a shared credential section
// would be a schema change plus a migration for already-pasted tokens.

/// How many rows a face has room for. `prCount` is the large count; medium
/// physically cannot show more than three rows and stay readable.
enum PRBoxFace {
    case medium
    case large
}

struct PRGitHubSettings: Codable, Equatable {
    /// Off by default: a widget added from the gallery must not start making
    /// network requests on its own.
    var enabled = false
    /// Personal access token — required; no default is ever sent.
    var token = ""
    /// Optional extra search terms ("org:acme", "repo:owner/name"). Empty
    /// searches everything the token can see, which on a long-lived account
    /// reaches years back into personal repositories.
    var scope = ""
    /// The credential this widget uses, by `CredentialAccount.id`. `nil` means
    /// no account is selected, which reads as "not configured".
    var accountID: String?

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        token = try c.decodeIfPresent(String.self, forKey: .token) ?? ""
        accountID = try c.decodeIfPresent(String.self, forKey: .accountID)
        scope = try c.decodeIfPresent(String.self, forKey: .scope) ?? ""
    }
}

struct PRAzureSettings: Codable, Equatable {
    var enabled = false
    /// The credential this widget uses, by `CredentialAccount.id`. `nil` means
    /// no account is selected, which reads as "not configured".
    var accountID: String?
    /// Organization — a bare name or a full dev.azure.com URL.
    var organization = ""
    /// Project within the organization. The pull-request query is scoped to it.
    var project = ""
    /// Personal access token — required; no default is ever sent.
    var token = ""
    /// Prefix each Azure row with its project. Off by default; see
    /// `TaskBoxSettings.showProject`.
    var showProject = false

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        showProject = try c.decodeIfPresent(Bool.self, forKey: .showProject) ?? false
        organization = try c.decodeIfPresent(String.self, forKey: .organization) ?? ""
        project = try c.decodeIfPresent(String.self, forKey: .project) ?? ""
        token = try c.decodeIfPresent(String.self, forKey: .token) ?? ""
        accountID = try c.decodeIfPresent(String.self, forKey: .accountID)
    }
}

struct PRBoxSettings: Codable, Equatable {
    var github = PRGitHubSettings()
    var azure = PRAzureSettings()
    var showList = true
    /// Rows on the large face, 3...12. Medium shows at most three.
    var prCount = 6
    /// Per-row review-state glyph (approved / changes requested). Off hides
    /// the glyphs and skips the GitHub per-PR fetches — don't pay the rate
    /// budget for a feature the user hid. Azure costs nothing either way.
    var showReviewState = true
    var mineColor = RGBA.systemBlue
    var reviewColor = RGBA.systemOrange

    static let rowCountRange = 3...12

    func rowCount(for face: PRBoxFace) -> Int {
        switch face {
        case .medium: return min(prCount, 3)
        case .large: return prCount
        }
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        github = try c.decodeIfPresent(PRGitHubSettings.self, forKey: .github) ?? PRGitHubSettings()
        azure = try c.decodeIfPresent(PRAzureSettings.self, forKey: .azure) ?? PRAzureSettings()
        showList = try c.decodeIfPresent(Bool.self, forKey: .showList) ?? true
        let rawCount = try c.decodeIfPresent(Int.self, forKey: .prCount) ?? 6
        prCount = min(max(rawCount, Self.rowCountRange.lowerBound), Self.rowCountRange.upperBound)
        showReviewState = try c.decodeIfPresent(Bool.self, forKey: .showReviewState) ?? true
        mineColor = try c.decodeIfPresent(RGBA.self, forKey: .mineColor) ?? RGBA.systemBlue
        reviewColor = try c.decodeIfPresent(RGBA.self, forKey: .reviewColor) ?? RGBA.systemOrange
    }
}

// MARK: - MarketBox

struct MarketBoxSettings: Codable, Equatable {
    /// The configured symbols in display order, deduped and uppercased; at
    /// most `maxCount`. Picked from the curated list in the settings tab —
    /// the free-text field was retired because symbols typed blind were
    /// unknowable to the user.
    var tickers = ["BTC", "ETH", "USD", "GOLD"]
    /// The one display currency every row is priced in.
    var displayCurrency = MarketCurrency.usd
    /// Rows on the large face (1...12). Medium shows at most 4, small at most
    /// 4 — past that the rows are clipped by the frame rather than by the
    /// setting.
    var tickerCount = 8
    /// Day change applies to crypto rows on medium/large only — the small face
    /// is price-only, and fiat/gold always show "–".
    var showDayChange = true
    var upColor = RGBA.systemGreen
    var downColor = RGBA.systemRed
    var accentColor = RGBA.systemBlue

    static let maxCount = 12

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // `symbols` was the comma-separated free-text shape this widget shipped
        // with. Carry it over rather than silently resetting someone's list;
        // a file with neither key keeps the default list.
        let legacy = try c.decodeIfPresent(String.self, forKey: .legacySymbols)
        if let decoded = try c.decodeIfPresent([String].self, forKey: .tickers) {
            tickers = Self.normalized(decoded)
        } else if let legacy {
            tickers = MarketSymbolResolver.normalizedSymbols(from: legacy)
        } else {
            tickers = ["BTC", "ETH", "USD", "GOLD"]
        }
        displayCurrency = MarketCurrency(rawValue: try c.decodeIfPresent(String.self, forKey: .displayCurrency) ?? "") ?? .usd
        // Floor at 1, cap at maxCount so a hand-edited file cannot push more
        // rows into the face than it can lay out.
        tickerCount = min(max(try c.decodeIfPresent(Int.self, forKey: .tickerCount) ?? 8, 1), Self.maxCount)
        showDayChange = try c.decodeIfPresent(Bool.self, forKey: .showDayChange) ?? true
        upColor = try c.decodeIfPresent(RGBA.self, forKey: .upColor) ?? RGBA.systemGreen
        downColor = try c.decodeIfPresent(RGBA.self, forKey: .downColor) ?? RGBA.systemRed
        accentColor = try c.decodeIfPresent(RGBA.self, forKey: .accentColor) ?? RGBA.systemBlue
    }

    /// Writes only the current shape: the legacy `symbols` key is read on the
    /// way in (see `init(from:)`) and dropped on the way out, so a file
    /// migrates once and then stays clean.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(tickers, forKey: .tickers)
        try c.encode(displayCurrency, forKey: .displayCurrency)
        try c.encode(tickerCount, forKey: .tickerCount)
        try c.encode(showDayChange, forKey: .showDayChange)
        try c.encode(upColor, forKey: .upColor)
        try c.encode(downColor, forKey: .downColor)
        try c.encode(accentColor, forKey: .accentColor)
    }

    /// Uppercased, deduped, capped at `maxCount`, empty symbols dropped.
    static func normalized(_ symbols: [String]) -> [String] {
        var seen: [String] = []
        for symbol in symbols {
            let s = symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            if !s.isEmpty, !seen.contains(s) {
                seen.append(s)
            }
            if seen.count == maxCount { break }
        }
        return seen
    }

    private enum CodingKeys: String, CodingKey {
        case tickers, displayCurrency, tickerCount
        case showDayChange, upColor, downColor, accentColor
        case legacySymbols = "symbols"
    }
}

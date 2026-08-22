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
    var agentAtLogin = true

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
        case weatherbox, clockbox, shipbox, taskbox, calbox, agentAtLogin
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
        agentAtLogin = try c.decodeIfPresent(Bool.self, forKey: .agentAtLogin) ?? true
    }

    /// Settings live inside the widget extension's sandbox container so both
    /// the (unsandboxed) host app and the sandboxed extension can use them.
    /// NOTE: inside the sandbox, homeDirectoryForCurrentUser already points at
    /// the container (…/Containers/com.deck.app.widgets/Data), so the two
    /// resolve to the same absolute path.
    static var containerDirectory: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let isSandboxed = ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil
        if isSandboxed {
            return home.appendingPathComponent("Library/Application Support/Deck", isDirectory: true)
        }
        return home.appendingPathComponent("Library/Containers/com.deck.app.widgets/Data/Library/Application Support/Deck", isDirectory: true)
    }

    static var fileURL: URL {
        containerDirectory.appendingPathComponent("settings.json")
    }

    static func load() -> DeckSettings {
        guard let data = try? Data(contentsOf: Self.fileURL) else { return DeckSettings() }
        return (try? JSONDecoder().decode(DeckSettings.self, from: data)) ?? DeckSettings()
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        _ = AtomicFile.write(data, to: Self.fileURL)
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
    var cpuColor = RGBA(.green)
    var memColor = RGBA(.cyan)
    var diskColor = RGBA(.orange)
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
        cpuColor = try c.decodeIfPresent(RGBA.self, forKey: .cpuColor) ?? RGBA(.green)
        memColor = try c.decodeIfPresent(RGBA.self, forKey: .memColor) ?? RGBA(.cyan)
        diskColor = try c.decodeIfPresent(RGBA.self, forKey: .diskColor) ?? RGBA(.orange)
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
    var inputColor = RGBA(.cyan)
    var outputColor = RGBA(.green)
    var costColor = RGBA(.orange)

    /// Tolerant decode: missing keys keep the defaults instead of throwing
    /// (the synthesized decoder throws, which would reset every setting via
    /// `DeckSettings.load()`'s fallback when old settings.json files lack
    /// newly added keys).
    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        token = try c.decodeIfPresent(String.self, forKey: .token) ?? ""
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
        inputColor = try c.decodeIfPresent(RGBA.self, forKey: .inputColor) ?? RGBA(.cyan)
        outputColor = try c.decodeIfPresent(RGBA.self, forKey: .outputColor) ?? RGBA(.green)
        costColor = try c.decodeIfPresent(RGBA.self, forKey: .costColor) ?? RGBA(.orange)
    }
}

struct NetBoxSettings: Codable, Equatable {
    var showChart = true
    var showInterfaces = true
    var interfaceCount = 3
    /// Non-empty → pinned to one interface; nil → auto "most active".
    var pinnedInterface: String?
    var upColor = RGBA(.green)
    var downColor = RGBA(.cyan)
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
        upColor = try c.decodeIfPresent(RGBA.self, forKey: .upColor) ?? RGBA(.green)
        downColor = try c.decodeIfPresent(RGBA.self, forKey: .downColor) ?? RGBA(.cyan)
        showThresholdColors = try c.decodeIfPresent(Bool.self, forKey: .showThresholdColors) ?? true
        // Floor at 1 so a hand-edited 0 can never make every rate an alarm.
        warnThreshold = max(1, try c.decodeIfPresent(Int.self, forKey: .warnThreshold) ?? 50)
        alarmThreshold = max(1, try c.decodeIfPresent(Int.self, forKey: .alarmThreshold) ?? 100)
    }
}

struct BatBoxSettings: Codable, Equatable {
    var showChart = true
    var showStatus = true
    var levelColor = RGBA(.green)

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        showChart = try c.decodeIfPresent(Bool.self, forKey: .showChart) ?? true
        showStatus = try c.decodeIfPresent(Bool.self, forKey: .showStatus) ?? true
        levelColor = try c.decodeIfPresent(RGBA.self, forKey: .levelColor) ?? RGBA(.green)
    }
}

struct GitBoxSettings: Codable, Equatable {
    var showChart = true
    var showRepos = true
    var repoCount = 5
    var scanDepth = 3
    var repoPaths: [String] = []
    var barColor = RGBA(.blue)
    var todayColor = RGBA(.orange)

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        showChart = try c.decodeIfPresent(Bool.self, forKey: .showChart) ?? true
        showRepos = try c.decodeIfPresent(Bool.self, forKey: .showRepos) ?? true
        repoCount = try c.decodeIfPresent(Int.self, forKey: .repoCount) ?? 5
        scanDepth = try c.decodeIfPresent(Int.self, forKey: .scanDepth) ?? 3
        repoPaths = try c.decodeIfPresent([String].self, forKey: .repoPaths) ?? []
        barColor = try c.decodeIfPresent(RGBA.self, forKey: .barColor) ?? RGBA(.blue)
        todayColor = try c.decodeIfPresent(RGBA.self, forKey: .todayColor) ?? RGBA(.orange)
    }
}

struct DevBoxSettings: Codable, Equatable {
    var showPorts = true
    var showContainers = true
    var portCount = 5
    var containerCount = 5
    var portColor = RGBA(.teal)
    var containerColor = RGBA(.mint)

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        showPorts = try c.decodeIfPresent(Bool.self, forKey: .showPorts) ?? true
        showContainers = try c.decodeIfPresent(Bool.self, forKey: .showContainers) ?? true
        portCount = try c.decodeIfPresent(Int.self, forKey: .portCount) ?? 5
        containerCount = try c.decodeIfPresent(Int.self, forKey: .containerCount) ?? 5
        portColor = try c.decodeIfPresent(RGBA.self, forKey: .portColor) ?? RGBA(.teal)
        containerColor = try c.decodeIfPresent(RGBA.self, forKey: .containerColor) ?? RGBA(.mint)
    }
}

struct ClipBoxSettings: Codable, Equatable {
    var showList = true
    var historyCount = 5
    var textColor = RGBA(.indigo)
    var imageColor = RGBA(.pink)
    var fileColor = RGBA(.blue)
    var otherColor = RGBA(.gray)

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        showList = try c.decodeIfPresent(Bool.self, forKey: .showList) ?? true
        historyCount = try c.decodeIfPresent(Int.self, forKey: .historyCount) ?? 5
        textColor = try c.decodeIfPresent(RGBA.self, forKey: .textColor) ?? RGBA(.indigo)
        imageColor = try c.decodeIfPresent(RGBA.self, forKey: .imageColor) ?? RGBA(.pink)
        fileColor = try c.decodeIfPresent(RGBA.self, forKey: .fileColor) ?? RGBA(.blue)
        otherColor = try c.decodeIfPresent(RGBA.self, forKey: .otherColor) ?? RGBA(.gray)
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
    var showRelativeDay = true
    var showOffset = true
    var timeColor = RGBA(.teal)

    init() {}

    init(cityIDs: [String]) {
        self.cityIDs = Array(cityIDs.prefix(ClockBoxCore.maxCities))
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let decoded = try c.decodeIfPresent([String].self, forKey: .cityIDs)
            ?? [ClockBoxCore.localID, "UTC"]
        cityIDs = Array(decoded.prefix(ClockBoxCore.maxCities))
        showRelativeDay = try c.decodeIfPresent(Bool.self, forKey: .showRelativeDay) ?? true
        showOffset = try c.decodeIfPresent(Bool.self, forKey: .showOffset) ?? true
        timeColor = try c.decodeIfPresent(RGBA.self, forKey: .timeColor) ?? RGBA(.teal)
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

struct ShipBoxSettings: Codable, Equatable {
    /// "owner/repo" — empty → agent skips the fetch.
    var repo = ""
    /// GitHub personal access token — required; no default is ever sent.
    var token = ""
    var showList = true
    var runCount = 4
    var queuedColor = RGBA(.orange)
    var runningColor = RGBA(.yellow)
    var successColor = RGBA(.green)
    var failureColor = RGBA(.red)

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        repo = try c.decodeIfPresent(String.self, forKey: .repo) ?? ""
        token = try c.decodeIfPresent(String.self, forKey: .token) ?? ""
        showList = try c.decodeIfPresent(Bool.self, forKey: .showList) ?? true
        runCount = try c.decodeIfPresent(Int.self, forKey: .runCount) ?? 4
        queuedColor = try c.decodeIfPresent(RGBA.self, forKey: .queuedColor) ?? RGBA(.orange)
        runningColor = try c.decodeIfPresent(RGBA.self, forKey: .runningColor) ?? RGBA(.yellow)
        successColor = try c.decodeIfPresent(RGBA.self, forKey: .successColor) ?? RGBA(.green)
        failureColor = try c.decodeIfPresent(RGBA.self, forKey: .failureColor) ?? RGBA(.red)
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
    /// The lane legend under the header.
    var showLegend = true
    var showList = true
    var taskCount = 5
    /// Which raw Azure DevOps states feed which lane. Editable because process
    /// templates get customised and board columns get renamed.
    var stateMapping = TaskStateMapping()
    var todoColor = RGBA(.blue)
    var inProgressColor = RGBA(.orange)
    var testingColor = RGBA(.purple)
    var doneColor = RGBA(.green)
    var otherColor = RGBA(.gray)

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        organization = try c.decodeIfPresent(String.self, forKey: .organization) ?? ""
        project = try c.decodeIfPresent(String.self, forKey: .project) ?? ""
        token = try c.decodeIfPresent(String.self, forKey: .token) ?? ""
        showLegend = try c.decodeIfPresent(Bool.self, forKey: .showLegend) ?? true
        showList = try c.decodeIfPresent(Bool.self, forKey: .showList) ?? true
        taskCount = try c.decodeIfPresent(Int.self, forKey: .taskCount) ?? 5
        stateMapping = try c.decodeIfPresent(TaskStateMapping.self, forKey: .stateMapping) ?? TaskStateMapping()
        todoColor = try c.decodeIfPresent(RGBA.self, forKey: .todoColor) ?? RGBA(.blue)
        inProgressColor = try c.decodeIfPresent(RGBA.self, forKey: .inProgressColor) ?? RGBA(.orange)
        testingColor = try c.decodeIfPresent(RGBA.self, forKey: .testingColor) ?? RGBA(.purple)
        doneColor = try c.decodeIfPresent(RGBA.self, forKey: .doneColor) ?? RGBA(.green)
        otherColor = try c.decodeIfPresent(RGBA.self, forKey: .otherColor) ?? RGBA(.gray)
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
    var accentColor = RGBA(.blue)

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
        accentColor = try c.decodeIfPresent(RGBA.self, forKey: .accentColor) ?? RGBA(.blue)
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
            set: { wrappedValue = RGBA($0) }
        )
    }
}

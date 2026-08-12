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

    static let green = RGBA(red: 0, green: 1, blue: 0)
    static let cyan = RGBA(red: 0, green: 1, blue: 1)
    static let orange = RGBA(red: 1, green: 0.5, blue: 0)
    static let blue = RGBA(red: 0, green: 0, blue: 1)
    static let teal = RGBA(red: 0, green: 0.5, blue: 0.5)
    static let mint = RGBA(red: 0.5, green: 1, blue: 0.6)
}

struct OpenBox: Codable, Equatable {
    var token = ""
    var serverURL: String?
    var refreshInterval = 60
    var showChart = true
    var showModels = true
    var inputColor = RGBA.cyan
    var outputColor = RGBA.green
    var costColor = RGBA.orange

    init(token: String = "", serverURL: String? = nil, refreshInterval: Int = 60,
         showChart: Bool = true, showModels: Bool = true,
         inputColor: RGBA = .cyan, outputColor: RGBA = .green, costColor: RGBA = .orange) {
        self.token = token
        self.serverURL = serverURL
        self.refreshInterval = refreshInterval
        self.showChart = showChart
        self.showModels = showModels
        self.inputColor = inputColor
        self.outputColor = outputColor
        self.costColor = costColor
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        token = try c.decodeIfPresent(String.self, forKey: .token) ?? ""
        serverURL = try c.decodeIfPresent(String.self, forKey: .serverURL)
        refreshInterval = try c.decodeIfPresent(Int.self, forKey: .refreshInterval) ?? 60
        showChart = try c.decodeIfPresent(Bool.self, forKey: .showChart) ?? true
        showModels = try c.decodeIfPresent(Bool.self, forKey: .showModels) ?? true
        inputColor = try c.decodeIfPresent(RGBA.self, forKey: .inputColor) ?? RGBA.cyan
        outputColor = try c.decodeIfPresent(RGBA.self, forKey: .outputColor) ?? RGBA.green
        costColor = try c.decodeIfPresent(RGBA.self, forKey: .costColor) ?? RGBA.orange
    }
}

struct NetBox: Codable, Equatable {
    var showChart = true
    var showInterfaces = true
    var interfaceCount = 3
    var upColor = RGBA.green
    var downColor = RGBA.cyan

    init(showChart: Bool = true, showInterfaces: Bool = true, interfaceCount: Int = 3,
         upColor: RGBA = .green, downColor: RGBA = .cyan) {
        self.showChart = showChart
        self.showInterfaces = showInterfaces
        self.interfaceCount = interfaceCount
        self.upColor = upColor
        self.downColor = downColor
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        showChart = try c.decodeIfPresent(Bool.self, forKey: .showChart) ?? true
        showInterfaces = try c.decodeIfPresent(Bool.self, forKey: .showInterfaces) ?? true
        interfaceCount = try c.decodeIfPresent(Int.self, forKey: .interfaceCount) ?? 3
        upColor = try c.decodeIfPresent(RGBA.self, forKey: .upColor) ?? RGBA.green
        downColor = try c.decodeIfPresent(RGBA.self, forKey: .downColor) ?? RGBA.cyan
    }
}

struct BatBox: Codable, Equatable {
    var showChart = true
    var showStatus = true
    var levelColor = RGBA.green

    init(showChart: Bool = true, showStatus: Bool = true, levelColor: RGBA = .green) {
        self.showChart = showChart
        self.showStatus = showStatus
        self.levelColor = levelColor
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        showChart = try c.decodeIfPresent(Bool.self, forKey: .showChart) ?? true
        showStatus = try c.decodeIfPresent(Bool.self, forKey: .showStatus) ?? true
        levelColor = try c.decodeIfPresent(RGBA.self, forKey: .levelColor) ?? RGBA.green
    }
}

struct GitBox: Codable, Equatable {
    var showChart = true
    var showRepos = true
    var repoCount = 5
    var scanDepth = 3
    var repoPaths: [String] = []
    var barColor = RGBA.blue
    var todayColor = RGBA.orange

    init(showChart: Bool = true, showRepos: Bool = true, repoCount: Int = 5, scanDepth: Int = 3,
         repoPaths: [String] = [], barColor: RGBA = .blue, todayColor: RGBA = .orange) {
        self.showChart = showChart
        self.showRepos = showRepos
        self.repoCount = repoCount
        self.scanDepth = scanDepth
        self.repoPaths = repoPaths
        self.barColor = barColor
        self.todayColor = todayColor
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        showChart = try c.decodeIfPresent(Bool.self, forKey: .showChart) ?? true
        showRepos = try c.decodeIfPresent(Bool.self, forKey: .showRepos) ?? true
        repoCount = try c.decodeIfPresent(Int.self, forKey: .repoCount) ?? 5
        scanDepth = try c.decodeIfPresent(Int.self, forKey: .scanDepth) ?? 3
        repoPaths = try c.decodeIfPresent([String].self, forKey: .repoPaths) ?? []
        barColor = try c.decodeIfPresent(RGBA.self, forKey: .barColor) ?? RGBA.blue
        todayColor = try c.decodeIfPresent(RGBA.self, forKey: .todayColor) ?? RGBA.orange
    }
}

struct DevBox: Codable, Equatable {
    var showPorts = true
    var showContainers = true
    var portCount = 5
    var containerCount = 5
    var portColor = RGBA.teal
    var containerColor = RGBA.mint

    init(showPorts: Bool = true, showContainers: Bool = true, portCount: Int = 5,
         containerCount: Int = 5, portColor: RGBA = .teal, containerColor: RGBA = .mint) {
        self.showPorts = showPorts
        self.showContainers = showContainers
        self.portCount = portCount
        self.containerCount = containerCount
        self.portColor = portColor
        self.containerColor = containerColor
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        showPorts = try c.decodeIfPresent(Bool.self, forKey: .showPorts) ?? true
        showContainers = try c.decodeIfPresent(Bool.self, forKey: .showContainers) ?? true
        portCount = try c.decodeIfPresent(Int.self, forKey: .portCount) ?? 5
        containerCount = try c.decodeIfPresent(Int.self, forKey: .containerCount) ?? 5
        portColor = try c.decodeIfPresent(RGBA.self, forKey: .portColor) ?? RGBA.teal
        containerColor = try c.decodeIfPresent(RGBA.self, forKey: .containerColor) ?? RGBA.mint
    }
}

import Foundation

public struct DayUsage: Identifiable, Equatable {
    public let day: String
    public let input: Int64
    public let output: Int64
    public var id: String { day }

    public init(day: String, input: Int64, output: Int64) {
        self.day = day
        self.input = input
        self.output = output
    }
}

public struct ModelUsage: Identifiable, Equatable {
    public let model: String
    public let provider: String
    public let modelID: String
    public let variant: String?
    public let cost: Double
    public let input: Int64
    public let output: Int64
    public var id: String { model }

    public init(
        model: String,
        provider: String,
        modelID: String,
        variant: String?,
        cost: Double,
        input: Int64,
        output: Int64
    ) {
        self.model = model
        self.provider = provider
        self.modelID = modelID
        self.variant = variant
        self.cost = cost
        self.input = input
        self.output = output
    }
}

public struct OpenCodeMetrics: Equatable {
    public var sessions: Int = 0
    public var messages: Int = 0
    public var input: Int64 = 0
    public var output: Int64 = 0
    public var cacheRead: Int64 = 0
    public var cacheWrite: Int64 = 0
    public var cost: Double = 0

    public var todaySessions: Int = 0
    public var todayInput: Int64 = 0
    public var todayOutput: Int64 = 0
    public var todayCost: Double = 0

    public var daily: [DayUsage] = []
    public var models: [ModelUsage] = []

    public init() {}
}

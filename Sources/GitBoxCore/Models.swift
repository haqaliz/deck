import Foundation

public struct RepoCommits: Equatable {
    public let shortName: String
    public let path: String
    public let todayCount: Int

    public init(shortName: String, path: String, todayCount: Int) {
        self.shortName = shortName
        self.path = path
        self.todayCount = todayCount
    }
}

public struct DayCommitCount: Equatable {
    public let day: String
    public let count: Int

    public init(day: String, count: Int) {
        self.day = day
        self.count = count
    }
}

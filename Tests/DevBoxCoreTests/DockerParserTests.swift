import XCTest
@testable import DevBoxCore

final class DockerParserTests: XCTestCase {

    func testJoinsStatsOntoRunningContainers() {
        let ps = """
        redis|redis:7-alpine|Up 2 hours
        """
        let stats = """
        redis|0.05%|2.31%
        """
        let result = DockerParser.parseContainers(psOutput: ps, statsOutput: stats)
        XCTAssertEqual(result.state, .running)
        XCTAssertEqual(result.containers, [
            ContainerInfo(name: "redis", image: "redis:7-alpine", status: "Up 2 hours", cpuPercent: 0.05, memPercent: 2.31)
        ])
    }

    func testMissingStatsRowYieldsNilPercentages() {
        let ps = """
        web|nginx:latest|Up 10 minutes
        db|postgres:16|Up 3 days
        """
        let stats = """
        web|1.20%|4.56%
        """
        let result = DockerParser.parseContainers(psOutput: ps, statsOutput: stats)
        XCTAssertEqual(result.containers[0].cpuPercent, 1.20)
        XCTAssertEqual(result.containers[0].memPercent, 4.56)
        XCTAssertNil(result.containers[1].cpuPercent)
        XCTAssertNil(result.containers[1].memPercent)
    }

    func testDropsStatsOnlyNames() {
        let ps = """
        web|nginx:latest|Up 10 minutes
        """
        let stats = """
        web|1.20%|4.56%
        web|dead-beef|2.00%|3.00%
        """
        let result = DockerParser.parseContainers(psOutput: ps, statsOutput: stats)
        XCTAssertEqual(result.containers.count, 1)
        XCTAssertEqual(result.containers[0].name, "web")
    }

    func testEmptyPsYieldsNoContainersState() {
        let stats = """
        ghost|1.00%|2.00%
        """
        let result = DockerParser.parseContainers(psOutput: "", statsOutput: stats)
        XCTAssertEqual(result.state, .noContainers)
        XCTAssertTrue(result.containers.isEmpty)
    }

    func testSwarmCommaJoinedNamesTakeFirst() {
        let ps = """
        redis,redis-worker|redis:7-alpine|Up 2 hours
        """
        let stats = """
        redis|0.05%|2.31%
        """
        let result = DockerParser.parseContainers(psOutput: ps, statsOutput: stats)
        XCTAssertEqual(result.containers.first?.name, "redis")
    }

    func testParsePercentHandlesValidGarbageAndEmpty() {
        XCTAssertEqual(DockerParser.parsePercent("0.05%"), 0.05)
        XCTAssertEqual(DockerParser.parsePercent("2.31%"), 2.31)
        XCTAssertEqual(DockerParser.parsePercent("2,31%"), nil)
        XCTAssertEqual(DockerParser.parsePercent("abc%"), nil)
        XCTAssertEqual(DockerParser.parsePercent(""), nil)
        XCTAssertEqual(DockerParser.parsePercent("12.5"), nil)
    }
}

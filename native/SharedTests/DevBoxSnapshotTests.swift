import XCTest

// Behavior pins for the DevBox lsof/docker parsers + formatters in
// Shared/DevBoxSnapshot.swift (ROADMAP.md:57, PRD §2).

final class LsofParserTests: XCTestCase {
    func testParsesBasicBlocks() {
        let raw = """
        p12345
        cnc
        n127.0.0.1:8080
        p12346
        cother
        n*:443
        """
        XCTAssertEqual(LsofParser.parse(raw), [
            PortInfo(command: "other", host: "*", port: 443),
            PortInfo(command: "nc", host: "127.0.0.1", port: 8080),
        ])
    }

    func testDeduplicatesIdenticalCommandAndAddress() {
        let raw = """
        p1
        cnc
        n127.0.0.1:8080
        n127.0.0.1:8080
        """
        XCTAssertEqual(LsofParser.parse(raw), [
            PortInfo(command: "nc", host: "127.0.0.1", port: 8080),
        ])
    }

    func testSkipsNameWithoutPriorCommand() {
        let raw = """
        p1
        n127.0.0.1:8080
        """
        XCTAssertEqual(LsofParser.parse(raw), [])
    }

    func testSkipsEmptyHostAndUnparseablePort() {
        let raw = """
        p1
        cnc
        n:8080
        n127.0.0.1:abc
        n127.0.0.1:8080
        """
        XCTAssertEqual(LsofParser.parse(raw), [
            PortInfo(command: "nc", host: "127.0.0.1", port: 8080),
        ])
    }

    func testParsesIPv6Address() {
        let raw = """
        p1
        cserver
        n[::1]:8443
        """
        XCTAssertEqual(LsofParser.parse(raw), [
            PortInfo(command: "server", host: "[::1]", port: 8443),
        ])
    }

    func testSortsByPortThenCommand() {
        let raw = """
        p1
        cz
        n127.0.0.1:9000
        p2
        ca
        n127.0.0.1:8000
        p3
        cb
        n127.0.0.1:8000
        """
        XCTAssertEqual(LsofParser.parse(raw), [
            PortInfo(command: "a", host: "127.0.0.1", port: 8000),
            PortInfo(command: "b", host: "127.0.0.1", port: 8000),
            PortInfo(command: "z", host: "127.0.0.1", port: 9000),
        ])
    }

    func testIgnoresPidAndUnknownTokens() {
        let raw = """
        p99
        cweb
        u123
        n0.0.0.0:80
        """
        XCTAssertEqual(LsofParser.parse(raw), [
            PortInfo(command: "web", host: "0.0.0.0", port: 80),
        ])
    }

    func testEmptyInputYieldsNoRows() {
        XCTAssertEqual(LsofParser.parse(""), [])
        XCTAssertEqual(LsofParser.parse("\n\n"), [])
    }
}

final class DockerParserTests: XCTestCase {
    func testJoinsStatsByIdentity() {
        let result = DockerParser.parseContainers(
            psOutput: "web|nginx:latest|Up 2 hours\ndb|postgres:16|Up 5 days",
            statsOutput: "web|0.05%|1.2%\ndb|0.10%|2.0%"
        )
        XCTAssertEqual(result.containers, [
            ContainerInfo(name: "web", image: "nginx:latest", status: "Up 2 hours", cpuPercent: 0.05, memPercent: 1.2),
            ContainerInfo(name: "db", image: "postgres:16", status: "Up 5 days", cpuPercent: 0.10, memPercent: 2.0),
        ])
        XCTAssertEqual(result.state, .running)
    }

    func testDropsStatsOnlyNames() {
        let result = DockerParser.parseContainers(
            psOutput: "web|nginx|Up",
            statsOutput: "web|0.05%|1.2%\norphan|9%|9%"
        )
        XCTAssertEqual(result.containers.map(\.name), ["web"])
    }

    func testMissingStatsKeepsNilPercents() {
        let result = DockerParser.parseContainers(
            psOutput: "web|nginx|Up",
            statsOutput: ""
        )
        XCTAssertEqual(result.containers, [
            ContainerInfo(name: "web", image: "nginx", status: "Up", cpuPercent: nil, memPercent: nil),
        ])
    }

    func testUsesFirstCommaComponentAsName() {
        let result = DockerParser.parseContainers(
            psOutput: "web,worker|img|Up",
            statsOutput: "web|1%|1%"
        )
        XCTAssertEqual(result.containers.map(\.name), ["web"])
    }

    func testEmptyPsIsNoContainers() {
        let result = DockerParser.parseContainers(psOutput: "", statsOutput: "")
        XCTAssertEqual(result.containers, [])
        XCTAssertEqual(result.state, .noContainers)
    }

    func testSkipsMalformedRows() {
        let result = DockerParser.parseContainers(
            psOutput: "broken\na|b\nweb|img|Up",
            statsOutput: "nolines\nweb|0.05%|1.2%"
        )
        XCTAssertEqual(result.containers.map(\.name), ["web"])
        XCTAssertEqual(result.containers[0].cpuPercent, 0.05)
    }

    func testGarbagePercentValuesBecomeNil() {
        let result = DockerParser.parseContainers(
            psOutput: "web|img|Up",
            statsOutput: "web|abc|xyz"
        )
        XCTAssertNil(result.containers[0].cpuPercent)
        XCTAssertNil(result.containers[0].memPercent)
    }
}

final class DockerParserPercentTests: XCTestCase {
    func testParsesPercent() {
        XCTAssertEqual(DockerParser.parsePercent("0.05%"), 0.05)
        XCTAssertEqual(DockerParser.parsePercent(" 1.2% "), 1.2)
        XCTAssertEqual(DockerParser.parsePercent("100%"), 100)
    }

    func testRejectsNonPercentAndGarbage() {
        XCTAssertNil(DockerParser.parsePercent("5"))
        XCTAssertNil(DockerParser.parsePercent("abc"))
        XCTAssertNil(DockerParser.parsePercent(""))
        XCTAssertNil(DockerParser.parsePercent("1.2.3%"))
        XCTAssertNil(DockerParser.parsePercent(".%"))
    }
}

final class DevBoxFormattersTests: XCTestCase {
    func testPortLabel() {
        XCTAssertEqual(Formatters.portLabel(host: "127.0.0.1", port: 8080), "127.0.0.1:8080")
        XCTAssertEqual(Formatters.portLabel(host: "*", port: 443), "*:443")
    }

    func testPercentString() {
        XCTAssertEqual(Formatters.percentString(12.3), "12.3%")
        XCTAssertEqual(Formatters.percentString(0), "0.0%")
        XCTAssertEqual(Formatters.percentString(nil), "—")
    }
}

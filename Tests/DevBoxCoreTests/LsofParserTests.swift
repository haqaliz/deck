import XCTest
@testable import DevBoxCore

final class LsofParserTests: XCTestCase {

    func testParsesRealSampleWithDeduplication() {
        let raw = """
        p990
        crapportd
        n*:63100
        n*:63100
        p1143
        cControlCenter
        n*:7000
        n*:7000
        """
        let ports = LsofParser.parse(raw)
        XCTAssertEqual(ports, [
            PortInfo(command: "ControlCenter", host: "*", port: 7000),
            PortInfo(command: "rapportd", host: "*", port: 63100),
        ])
    }

    func testKeepsDistinctHostsUnderSameCommand() {
        let raw = """
        p100
        credisserver
        n127.0.0.1:6379
        n[::1]:6379
        p200
        cweb
        n*:8080
        """
        let ports = LsofParser.parse(raw)
        XCTAssertEqual(ports, [
            PortInfo(command: "redisserver", host: "127.0.0.1", port: 6379),
            PortInfo(command: "redisserver", host: "[::1]", port: 6379),
            PortInfo(command: "web", host: "*", port: 8080),
        ])
    }

    func testSortsByPortAscendingRegardlessOfProcessOrder() {
        let raw = """
        p1
        czed
        n*:3000
        p2
        caaa
        n*:80
        """
        let ports = LsofParser.parse(raw)
        XCTAssertEqual(ports, [
            PortInfo(command: "aaa", host: "*", port: 80),
            PortInfo(command: "zed", host: "*", port: 3000),
        ])
    }

    func testSkipsGarbageAndUnparseableNames() {
        let raw = """
        p1
        cweird
        nno-colon-here
        n:8080
        n127.0.0.1:8080:extra
        p2
        cok
        n*:5000
        """
        let ports = LsofParser.parse(raw)
        XCTAssertEqual(ports, [
            PortInfo(command: "ok", host: "*", port: 5000),
        ])
    }

    func testEmptyInputYieldsEmptyList() {
        XCTAssertEqual(LsofParser.parse(""), [])
    }
}

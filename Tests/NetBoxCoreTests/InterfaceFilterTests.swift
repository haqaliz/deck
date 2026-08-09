import XCTest
@testable import NetBoxCore

final class InterfaceFilterTests: XCTestCase {
    func testPhysicalInterfacesIncluded() {
        XCTAssertTrue(InterfaceFilter.isIncluded("en0"))
        XCTAssertTrue(InterfaceFilter.isIncluded("en5"))
    }

    func testLoopbackExcluded() {
        XCTAssertFalse(InterfaceFilter.isIncluded("lo0"))
    }

    func testVirtualInterfacesExcluded() {
        for name in ["utun0", "utun58", "awdl0", "llw0", "anpi0", "anpi2", "ap1",
                     "bridge0", "vboxnet0", "vmnet8", "gif0", "stf0"] {
            XCTAssertFalse(InterfaceFilter.isIncluded(name), "\(name) should be excluded")
        }
    }

    func testUnknownInterfaceIncluded() {
        XCTAssertTrue(InterfaceFilter.isIncluded("foo0"))
    }

    func testIncludedFiltersList() {
        let samples = [
            InterfaceSample(name: "lo0", rxBytes: 0, txBytes: 0),
            InterfaceSample(name: "en0", rxBytes: 100, txBytes: 200),
            InterfaceSample(name: "utun3", rxBytes: 300, txBytes: 400),
        ]
        let included = InterfaceFilter.included(samples)
        XCTAssertEqual(included.map(\.name), ["en0"])
    }
}

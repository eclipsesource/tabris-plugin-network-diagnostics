@testable import NetworkDiagnostics
import XCTest

final class InterfaceParserTests: XCTestCase {
    private let upFlags = UInt32(IFF_UP | IFF_RUNNING | IFF_MULTICAST)

    func testGroupsAddressesByInterfaceAndSplitsFamilies() {
        let records = [
            RawInterfaceAddress(name: "en0", flags: upFlags, socketAddress: SocketAddressFixtures.ipv4("192.168.1.10")),
            RawInterfaceAddress(name: "en0", flags: upFlags, socketAddress: SocketAddressFixtures.ipv6("fe80::1")),
            RawInterfaceAddress(name: "pdp_ip0", flags: upFlags, socketAddress: SocketAddressFixtures.ipv6("2a00::5")),
        ]

        let interfaces = InterfaceParser.parse(records)

        XCTAssertEqual(interfaces, [
            NetworkInterfaceInfo(
                name: "en0",
                ipv4Addresses: ["192.168.1.10"],
                ipv6Addresses: ["fe80::1"],
                isUp: true,
                isLoopback: false
            ),
            NetworkInterfaceInfo(
                name: "pdp_ip0",
                ipv4Addresses: [],
                ipv6Addresses: ["2a00::5"],
                isUp: true,
                isLoopback: false
            ),
        ])
    }

    func testFlagsLoopbackAndDownInterfaces() {
        let records = [
            RawInterfaceAddress(
                name: "lo0",
                flags: upFlags | UInt32(IFF_LOOPBACK),
                socketAddress: SocketAddressFixtures.ipv4("127.0.0.1")
            ),
            RawInterfaceAddress(name: "en1", flags: 0, socketAddress: SocketAddressFixtures.ipv4("10.0.0.2")),
        ]

        let interfaces = InterfaceParser.parse(records)

        XCTAssertEqual(interfaces.map(\.isLoopback), [true, false])
        XCTAssertEqual(interfaces.map(\.isUp), [true, false])
    }

    func testPreservesFirstAppearanceOrder() {
        let records = [
            RawInterfaceAddress(name: "utun0", flags: upFlags, socketAddress: SocketAddressFixtures.ipv6("fd00::1")),
            RawInterfaceAddress(name: "en0", flags: upFlags, socketAddress: SocketAddressFixtures.ipv4("10.1.1.1")),
            RawInterfaceAddress(name: "utun0", flags: upFlags, socketAddress: SocketAddressFixtures.ipv4("10.8.0.1")),
        ]

        XCTAssertEqual(InterfaceParser.parse(records).map(\.name), ["utun0", "en0"])
    }

    func testEmptyInputProducesNoInterfaces() {
        XCTAssertTrue(InterfaceParser.parse([]).isEmpty)
    }
}

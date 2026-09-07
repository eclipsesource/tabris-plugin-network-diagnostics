@testable import NetworkDiagnostics
import XCTest

final class ICMPPacketTests: XCTestCase {
    /// RFC 1071 worked example: the one's-complement sum of these words is
    /// 0xDDF2, so the checksum is its complement 0x220D.
    func testChecksumMatchesRFC1071Example() {
        let data = Data([0x00, 0x01, 0xF2, 0x03, 0xF4, 0xF5, 0xF6, 0xF7])

        XCTAssertEqual(ICMPPacket.checksum(data), 0x220D)
    }

    func testChecksumHandlesOddLength() {
        XCTAssertEqual(ICMPPacket.checksum(Data([0x01, 0x02, 0x03])), ~UInt16(0x0102 + 0x0300))
    }

    func testIPv4EchoRequestHasValidChecksumAndFields() {
        let packet = ICMPPacket.echoRequest(family: .ipv4, identifier: 0xBEEF, sequence: 7, payload: Data([1, 2, 3]))

        XCTAssertEqual(packet.count, 11)
        XCTAssertEqual(packet[0], 8)
        XCTAssertEqual(packet[1], 0)
        XCTAssertEqual(Array(packet[4...7]), [0xBE, 0xEF, 0x00, 0x07])
        XCTAssertEqual(ICMPPacket.checksum(packet), 0)
    }

    func testIPv6EchoRequestLeavesChecksumToKernel() {
        let packet = ICMPPacket.echoRequest(family: .ipv6, identifier: 1, sequence: 2, payload: Data())

        XCTAssertEqual(packet[0], 128)
        XCTAssertEqual(Array(packet[2...3]), [0, 0])
    }

    func testParsesIPv4ReplyBehindIPHeader() {
        var reply = ICMPPacket.echoRequest(family: .ipv4, identifier: 0x1234, sequence: 9, payload: Data([9, 9]))
        reply[0] = 0
        reply[2] = 0
        reply[3] = 0
        let checksum = ICMPPacket.checksum(reply)
        reply[2] = UInt8(checksum >> 8)
        reply[3] = UInt8(checksum & 0xFF)
        let ipHeader = Data([0x45] + [UInt8](repeating: 0, count: 19))

        let parsed = ICMPPacket.parseEchoReply(datagram: ipHeader + reply, family: .ipv4)

        XCTAssertEqual(parsed, ICMPEchoReply(identifier: 0x1234, sequence: 9, payload: Data([9, 9])))
    }

    func testRejectsIPv4ReplyWithBadChecksum() {
        var reply = ICMPPacket.echoRequest(family: .ipv4, identifier: 1, sequence: 1, payload: Data())
        reply[0] = 0
        let ipHeader = Data([0x45] + [UInt8](repeating: 0, count: 19))

        XCTAssertNil(ICMPPacket.parseEchoReply(datagram: ipHeader + reply, family: .ipv4))
    }

    func testParsesIPv6ReplyWithoutIPHeader() {
        let reply = Data([129, 0, 0, 0, 0xAB, 0xCD, 0x00, 0x03, 0x42])

        XCTAssertEqual(
            ICMPPacket.parseEchoReply(datagram: reply, family: .ipv6),
            ICMPEchoReply(identifier: 0xABCD, sequence: 3, payload: Data([0x42]))
        )
    }

    func testRejectsNonEchoReplyTypesAndShortDatagrams() {
        XCTAssertNil(ICMPPacket.parseEchoReply(datagram: Data([128, 0, 0, 0, 0, 0, 0, 0]), family: .ipv6))
        XCTAssertNil(ICMPPacket.parseEchoReply(datagram: Data([129, 0, 0]), family: .ipv6))
        XCTAssertNil(ICMPPacket.parseEchoReply(datagram: Data([0x45, 0x00]), family: .ipv4))
    }
}

@testable import NetworkDiagnostics
import XCTest

final class DNSMessageTests: XCTestCase {
    /// Header: id, flags RD, QDCOUNT 1, then `example.com` A IN.
    func testEncodesStandardRecursiveQuery() throws {
        let query = try XCTUnwrap(DNSMessage.query(domain: "example.com", identifier: 0xABCD))

        XCTAssertEqual(
            [UInt8](query),
            [
                0xAB, 0xCD, 0x01, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
                7, 0x65, 0x78, 0x61, 0x6D, 0x70, 0x6C, 0x65, 3, 0x63, 0x6F, 0x6D, 0,
                0x00, 0x01, 0x00, 0x01,
            ]
        )
    }

    func testAcceptsTrailingDotAndRejectsInvalidNames() {
        XCTAssertEqual(
            DNSMessage.query(domain: "apple.com.", identifier: 1),
            DNSMessage.query(domain: "apple.com", identifier: 1)
        )
        XCTAssertNil(DNSMessage.query(domain: "", identifier: 1))
        XCTAssertNil(DNSMessage.query(domain: "a..b", identifier: 1))
        XCTAssertNil(DNSMessage.query(domain: String(repeating: "x", count: 64) + ".com", identifier: 1))
    }

    /// Response to the query above with two A records; the answer names use a
    /// compression pointer (0xC00C) back to the question name.
    func testParsesAnswersWithCompressionPointers() {
        let response = Data(
            [
                0xAB, 0xCD, 0x81, 0x80, 0x00, 0x01, 0x00, 0x02, 0x00, 0x00, 0x00, 0x00,
                7, 0x65, 0x78, 0x61, 0x6D, 0x70, 0x6C, 0x65, 3, 0x63, 0x6F, 0x6D, 0,
                0x00, 0x01, 0x00, 0x01,
                0xC0, 0x0C, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00, 0x0E, 0x10, 0x00, 0x04, 93, 184, 216, 34,
                0xC0, 0x0C, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00, 0x0E, 0x10, 0x00, 0x04, 93, 184, 216, 35,
            ]
        )

        XCTAssertEqual(
            DNSMessage.parseResponse(response),
            DNSResponse(identifier: 0xABCD, responseCode: .noError, addresses: ["93.184.216.34", "93.184.216.35"])
        )
    }

    func testSkipsCNAMEAndKeepsAAAARecords() {
        let response = Data(
            [
                0x00, 0x01, 0x81, 0x80, 0x00, 0x01, 0x00, 0x02, 0x00, 0x00, 0x00, 0x00,
                1, 0x61, 0,
                0x00, 0x01, 0x00, 0x01,
                0xC0, 0x0C, 0x00, 0x05, 0x00, 0x01, 0x00, 0x00, 0x00, 0x3C, 0x00, 0x03, 1, 0x62, 0,
                0xC0, 0x0C, 0x00, 0x1C, 0x00, 0x01, 0x00, 0x00, 0x00, 0x3C, 0x00, 0x10,
                0x20, 0x01, 0x0D, 0xB8, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0x01,
            ]
        )

        XCTAssertEqual(DNSMessage.parseResponse(response)?.addresses, ["2001:db8::1"])
    }

    func testReportsNXDOMAINWithoutAnswers() {
        let response = Data(
            [0x12, 0x34, 0x81, 0x83, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 1, 0x61, 0, 0, 1, 0, 1]
        )

        XCTAssertEqual(
            DNSMessage.parseResponse(response),
            DNSResponse(identifier: 0x1234, responseCode: .nameError, addresses: [])
        )
    }

    func testRejectsQueriesTruncatedMessagesAndBadPointers() {
        let query = Data([0, 1, 0x01, 0x00, 0, 1, 0, 0, 0, 0, 0, 0, 1, 0x61, 0, 0, 1, 0, 1])
        let truncatedHeader = Data([0, 1, 0x81, 0x80])
        let danglingPointer = Data([0, 1, 0x81, 0x80, 0, 1, 0, 1, 0, 0, 0, 0, 1, 0x61, 0, 0, 1, 0, 1, 0xC0])

        XCTAssertNil(DNSMessage.parseResponse(query))
        XCTAssertNil(DNSMessage.parseResponse(truncatedHeader))
        XCTAssertNil(DNSMessage.parseResponse(danglingPointer))
    }
}

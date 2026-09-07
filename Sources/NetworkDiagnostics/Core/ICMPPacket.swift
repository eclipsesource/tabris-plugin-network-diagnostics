import Foundation

struct ICMPEchoReply: Equatable {
    let identifier: UInt16
    let sequence: UInt16
    let payload: Data
}

enum ICMPPacket {
    static let headerBytes = 8

    static func echoRequest(
        family: InternetAddress.Family,
        identifier: UInt16,
        sequence: UInt16,
        payload: Data
    ) -> Data {
        var packet = Data(capacity: headerBytes + payload.count)
        packet.append(family.echoRequestType)
        packet.append(0)
        packet.append(contentsOf: [0, 0])
        packet.append(contentsOf: bigEndianBytes(identifier))
        packet.append(contentsOf: bigEndianBytes(sequence))
        packet.append(payload)
        if family == .ipv4 {
            let checksum = bigEndianBytes(checksum(packet))
            packet[2] = checksum[0]
            packet[3] = checksum[1]
        }
        return packet
    }

    static func parseEchoReply(datagram: Data, family: InternetAddress.Family) -> ICMPEchoReply? {
        guard let message = icmpMessage(in: datagram, family: family), message.count >= headerBytes else { return nil }
        let type = message[message.startIndex]
        let code = message[message.startIndex + 1]

        guard type == family.echoReplyType, code == 0 else { return nil }
        guard family == .ipv6 || checksum(message) == 0 else { return nil }
        return ICMPEchoReply(
            identifier: readUInt16(message, at: 4),
            sequence: readUInt16(message, at: 6),
            payload: Data(message.dropFirst(headerBytes))
        )
    }

    static func checksum(_ data: Data) -> UInt16 {
        var sum: UInt32 = 0
        var index = data.startIndex

        while index + 1 < data.endIndex {
            sum += UInt32(data[index]) << 8 | UInt32(data[index + 1])
            index += 2
        }
        if index < data.endIndex {
            sum += UInt32(data[index]) << 8
        }
        while sum >> 16 != 0 {
            sum = (sum & 0xFFFF) + (sum >> 16)
        }
        return ~UInt16(truncatingIfNeeded: sum)
    }

    private static func icmpMessage(in datagram: Data, family: InternetAddress.Family) -> Data? {
        guard family == .ipv4 else { return datagram }
        guard let firstByte = datagram.first, firstByte >> 4 == 4 else { return nil }
        let headerLength = Int(firstByte & 0x0F) * 4

        guard datagram.count >= headerLength else { return nil }
        return datagram.dropFirst(headerLength)
    }

    private static func bigEndianBytes(_ value: UInt16) -> [UInt8] {
        [UInt8(value >> 8), UInt8(value & 0xFF)]
    }

    private static func readUInt16(_ data: Data, at offset: Int) -> UInt16 {
        let start = data.startIndex + offset

        return UInt16(data[start]) << 8 | UInt16(data[start + 1])
    }
}

extension InternetAddress.Family {
    var echoRequestType: UInt8 {
        switch self {
        case .ipv4: 8
        case .ipv6: 128
        }
    }

    var echoReplyType: UInt8 {
        switch self {
        case .ipv4: 0
        case .ipv6: 129
        }
    }
}

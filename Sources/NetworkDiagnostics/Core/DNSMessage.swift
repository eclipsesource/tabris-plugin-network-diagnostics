import Foundation

struct DNSResponse: Equatable {
    let identifier: UInt16
    let responseCode: DNSResponseCode
    let addresses: [String]
}

enum DNSMessage {
    private static let headerBytes = 12
    private static let recordTypeA: UInt16 = 1
    private static let recordTypeAAAA: UInt16 = 28
    private static let classInternet: UInt16 = 1
    private static let recursionDesiredFlags: UInt16 = 0x0100
    private static let maxLabelBytes = 63
    private static let maxNameBytes = 253

    static func query(domain: String, identifier: UInt16) -> Data? {
        guard let name = encodeName(domain) else { return nil }
        var message = Data()

        message.append(contentsOf: bigEndian(identifier))
        message.append(contentsOf: bigEndian(recursionDesiredFlags))
        message.append(contentsOf: bigEndian(1))
        message.append(contentsOf: [0, 0, 0, 0, 0, 0])
        message.append(name)
        message.append(contentsOf: bigEndian(recordTypeA))
        message.append(contentsOf: bigEndian(classInternet))
        return message
    }

    static func parseResponse(_ data: Data) -> DNSResponse? {
        let bytes = [UInt8](data)

        guard bytes.count >= headerBytes else { return nil }
        let flags = readUInt16(bytes, at: 2)

        guard flags & 0x8000 != 0 else { return nil }
        let questionCount = Int(readUInt16(bytes, at: 4))
        let answerCount = Int(readUInt16(bytes, at: 6))
        var offset = headerBytes

        for _ in 0..<questionCount {
            guard let nameEnd = skipName(bytes, at: offset), nameEnd + 4 <= bytes.count else { return nil }
            offset = nameEnd + 4
        }
        guard let addresses = parseAnswers(bytes, count: answerCount, at: offset) else { return nil }
        return DNSResponse(
            identifier: readUInt16(bytes, at: 0),
            responseCode: DNSResponseCode(rawCode: Int(flags & 0x000F)),
            addresses: addresses
        )
    }

    private static func parseAnswers(_ bytes: [UInt8], count: Int, at start: Int) -> [String]? {
        var offset = start
        var addresses: [String] = []

        for _ in 0..<count {
            guard let nameEnd = skipName(bytes, at: offset), nameEnd + 10 <= bytes.count else { return nil }
            let recordType = readUInt16(bytes, at: nameEnd)
            let dataLength = Int(readUInt16(bytes, at: nameEnd + 8))
            let dataStart = nameEnd + 10

            guard dataStart + dataLength <= bytes.count else { return nil }
            if let address = address(type: recordType, bytes: bytes[dataStart..<dataStart + dataLength]) {
                addresses.append(address)
            }
            offset = dataStart + dataLength
        }
        return addresses
    }

    private static func address(type: UInt16, bytes: ArraySlice<UInt8>) -> String? {
        switch type {
        case recordTypeA where bytes.count == 4:
            return InternetAddress(family: .ipv4, rawBytes: Data(bytes))?.description
        case recordTypeAAAA where bytes.count == 16:
            return InternetAddress(family: .ipv6, rawBytes: Data(bytes))?.description
        default:
            return nil
        }
    }

    private static func skipName(_ bytes: [UInt8], at start: Int) -> Int? {
        var offset = start

        while offset < bytes.count {
            let length = Int(bytes[offset])

            if length == 0 {
                return offset + 1
            }
            if length & 0xC0 == 0xC0 {
                return offset + 2 <= bytes.count ? offset + 2 : nil
            }
            offset += 1 + length
        }
        return nil
    }

    private static func encodeName(_ domain: String) -> Data? {
        let labels = domain.split(separator: ".", omittingEmptySubsequences: false).map { Array($0.utf8) }
        let trimmed = labels.last?.isEmpty == true ? Array(labels.dropLast()) : labels

        guard !trimmed.isEmpty,
              trimmed.allSatisfy({ !$0.isEmpty && $0.count <= maxLabelBytes }),
              domain.utf8.count <= maxNameBytes
        else { return nil }
        var name = Data()

        for label in trimmed {
            name.append(UInt8(label.count))
            name.append(contentsOf: label)
        }
        name.append(0)
        return name
    }

    private static func bigEndian(_ value: UInt16) -> [UInt8] {
        [UInt8(value >> 8), UInt8(value & 0xFF)]
    }

    private static func readUInt16(_ bytes: [UInt8], at offset: Int) -> UInt16 {
        UInt16(bytes[offset]) << 8 | UInt16(bytes[offset + 1])
    }
}

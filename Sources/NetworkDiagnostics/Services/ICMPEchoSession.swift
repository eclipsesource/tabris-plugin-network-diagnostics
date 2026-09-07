import Foundation

final class ICMPEchoSession: @unchecked Sendable {
    private static let payload = Data(repeating: 0x5A, count: 56)
    private static let receiveBufferBytes = 65_535

    private let queue = DispatchQueue(label: "NetworkDiagnostics.icmp")
    private let address: InternetAddress
    private let packetCount: Int
    private let timeoutPerPacketSeconds: TimeInterval
    private let identifier = UInt16.random(in: 0...UInt16.max)
    private var socketDescriptor: Int32 = -1
    private var readSource: DispatchSourceRead?
    private var sequence: UInt16 = 0
    private var sentPackets = 0
    private var rttSamplesMs: [Double] = []
    private var sentAt: ContinuousClock.Instant?
    private var timeoutWorkItem: DispatchWorkItem?
    private var completion: (@Sendable (PingOutcome) -> Void)?
    private var isCancelled = false

    init(address: InternetAddress, packetCount: Int, timeoutPerPacketSeconds: TimeInterval) {
        self.address = address
        self.packetCount = packetCount
        self.timeoutPerPacketSeconds = timeoutPerPacketSeconds
    }

    func start(completion: @escaping @Sendable (PingOutcome) -> Void) {
        queue.async {
            self.completion = completion
            if self.isCancelled {
                self.finish(with: .failed(reason: "ping of \(self.address) was cancelled before it started"))
            } else {
                self.openSocket()
            }
        }
    }

    func cancel() {
        queue.async {
            self.isCancelled = true
            self.finish(
                with: .failed(reason: "ping of \(self.address) was cancelled after \(self.sentPackets) packets")
            )
        }
    }

    private func openSocket() {
        let descriptor = socket(address.family.addressFamily, SOCK_DGRAM, address.family.icmpProtocol)

        guard descriptor >= 0 else {
            finish(with: .failed(reason: "socket(SOCK_DGRAM, ICMP) failed: \(String(cString: strerror(errno)))"))
            return
        }
        socketDescriptor = descriptor
        let source = DispatchSource.makeReadSource(fileDescriptor: descriptor, queue: queue)

        source.setEventHandler { [weak self] in self?.receive() }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        readSource = source
        sendNext()
    }

    private func sendNext() {
        guard sentPackets < packetCount else {
            finish(with: PingOutcome(sentPackets: sentPackets, rttSamplesMs: rttSamplesMs))
            return
        }
        let packet = ICMPPacket.echoRequest(
            family: address.family,
            identifier: identifier,
            sequence: sequence,
            payload: Self.payload
        )
        let sentBytes = address.withSocketAddress { pointer, length in
            packet.withUnsafeBytes { sendto(socketDescriptor, $0.baseAddress, $0.count, 0, pointer, length) }
        }

        guard sentBytes == packet.count else {
            finish(with: .failed(reason: "sendto(\(address)) failed: \(String(cString: strerror(errno)))"))
            return
        }
        sentPackets += 1
        sentAt = .now
        let timeout = DispatchWorkItem { [weak self] in self?.advance() }

        timeoutWorkItem = timeout
        queue.asyncAfter(deadline: .now() + timeoutPerPacketSeconds, execute: timeout)
    }

    private func receive() {
        var buffer = [UInt8](repeating: 0, count: Self.receiveBufferBytes)
        let receivedBytes = recv(socketDescriptor, &buffer, buffer.count, 0)

        guard receivedBytes > 0,
              let reply = ICMPPacket.parseEchoReply(datagram: Data(buffer[..<receivedBytes]), family: address.family),
              reply.identifier == identifier,
              reply.sequence == sequence,
              let sentAt
        else { return }
        rttSamplesMs.append((ContinuousClock.now - sentAt).milliseconds)
        advance()
    }

    private func advance() {
        timeoutWorkItem?.cancel()
        timeoutWorkItem = nil
        sequence &+= 1
        sendNext()
    }

    private func finish(with outcome: PingOutcome) {
        guard let completion else { return }
        self.completion = nil
        timeoutWorkItem?.cancel()
        readSource?.cancel()
        completion(outcome)
    }
}

extension InternetAddress.Family {
    var icmpProtocol: Int32 {
        switch self {
        case .ipv4: IPPROTO_ICMP
        case .ipv6: IPPROTO_ICMPV6
        }
    }
}

extension InternetAddress {
    func withSocketAddress<Output>(_ body: (UnsafePointer<sockaddr>, socklen_t) -> Output) -> Output {
        switch family {
        case .ipv4:
            var storage = sockaddr_in()

            storage.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            storage.sin_family = sa_family_t(AF_INET)
            storage.sin_addr = rawBytes.withUnsafeBytes { $0.loadUnaligned(as: in_addr.self) }
            return withUnsafePointer(to: &storage) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    body($0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        case .ipv6:
            var storage = sockaddr_in6()

            storage.sin6_len = UInt8(MemoryLayout<sockaddr_in6>.size)
            storage.sin6_family = sa_family_t(AF_INET6)
            storage.sin6_addr = rawBytes.withUnsafeBytes { $0.loadUnaligned(as: in6_addr.self) }
            return withUnsafePointer(to: &storage) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    body($0, socklen_t(MemoryLayout<sockaddr_in6>.size))
                }
            }
        }
    }
}

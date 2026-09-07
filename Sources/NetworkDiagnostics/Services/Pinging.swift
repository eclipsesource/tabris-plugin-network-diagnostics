import Foundation

protocol Pinging: Sendable {
    func ping(address: InternetAddress, packetCount: Int, timeoutPerPacketSeconds: TimeInterval) async -> PingOutcome
}

struct ICMPPinger: Pinging {
    func ping(address: InternetAddress, packetCount: Int, timeoutPerPacketSeconds: TimeInterval) async -> PingOutcome {
        let session = ICMPEchoSession(
            address: address,
            packetCount: packetCount,
            timeoutPerPacketSeconds: timeoutPerPacketSeconds
        )

        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                session.start { continuation.resume(returning: $0) }
            }
        } onCancel: {
            session.cancel()
        }
    }
}

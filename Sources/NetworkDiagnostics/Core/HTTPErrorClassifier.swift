import Foundation

enum HTTPErrorClassifier {
    static func classify(_ error: any Error) -> HttpFailure {
        guard let urlError = error as? URLError else {
            return .other(description: String(describing: error))
        }
        switch urlError.code {
        case .cannotFindHost, .dnsLookupFailed:
            return .dnsResolutionFailed
        case .secureConnectionFailed,
            .serverCertificateHasBadDate,
            .serverCertificateUntrusted,
            .serverCertificateHasUnknownRoot,
            .serverCertificateNotYetValid,
            .clientCertificateRejected,
            .clientCertificateRequired:
            return .tlsHandshakeFailed
        case .cannotConnectToHost:
            return .connectionRefused
        case .timedOut:
            return .timedOut
        case .notConnectedToInternet, .networkConnectionLost, .internationalRoamingOff, .dataNotAllowed:
            return .networkUnavailable
        default:
            return .other(description: "URLError \(urlError.code.rawValue): \(urlError.localizedDescription)")
        }
    }
}

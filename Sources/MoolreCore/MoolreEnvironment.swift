import Foundation

/// Moolre API environment used for both payment initiation and verification.
public enum MoolreEnvironment: String, CaseIterable, Codable, Sendable {
    case sandbox = "SANDBOX"
    case live = "LIVE"

    var paymentEndpoint: URL {
        switch self {
        case .sandbox: return URL(string: MoolreConstants.sandboxPaymentURL)!
        case .live: return URL(string: MoolreConstants.livePaymentURL)!
        }
    }

    var statusEndpoint: URL {
        switch self {
        case .sandbox: return URL(string: MoolreConstants.sandboxStatusURL)!
        case .live: return URL(string: MoolreConstants.liveStatusURL)!
        }
    }
}

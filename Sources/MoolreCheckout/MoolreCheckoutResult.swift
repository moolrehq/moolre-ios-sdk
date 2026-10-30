import Foundation

/// Raw result returned by checkout before server verification.
public enum MoolreCheckoutResult: Equatable, Sendable {
    /// Checkout reached the configured redirect with a transaction reference.
    case completed(reference: String)
    /// Checkout ended without a completed payment.
    case cancelled
    /// Checkout encountered a recoverable or configuration error.
    case failed(code: String, message: String)
}

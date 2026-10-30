import Foundation

/// Structured SDK failure that can be mapped to a stable public error code.
public struct MoolrePaymentError: Error, LocalizedError, Equatable, Sendable {
    public let code: String
    public let message: String

    public init(code: String, message: String) {
        self.code = code
        self.message = message
    }

    public var errorDescription: String? { message }

    static func invalidConfig(_ message: String) -> MoolrePaymentError {
        MoolrePaymentError(code: MoolreErrorCode.invalidConfig, message: message)
    }
}

extension String {
    var isBlank: Bool { trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}

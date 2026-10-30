import Foundation

/// Customer-facing payment values supplied for one payment attempt.
public struct MoolrePaymentRequest: Equatable, Sendable {
    public var amount: Decimal
    public var currency: String
    public var email: String
    public var reference: String?
    public var webhookURL: String?
    public var redirectURL: String?
    public var reusable: Bool
    public var expirationTimeMinutes: Int?
    public var metadata: [String: String]

    public init(
        amount: Decimal,
        currency: String = "GHS",
        email: String,
        reference: String? = nil,
        webhookURL: String? = nil,
        redirectURL: String? = nil,
        reusable: Bool = false,
        expirationTimeMinutes: Int? = nil,
        metadata: [String: String] = [:]
    ) {
        self.amount = amount
        self.currency = currency
        self.email = email
        self.reference = reference
        self.webhookURL = webhookURL
        self.redirectURL = redirectURL
        self.reusable = reusable
        self.expirationTimeMinutes = expirationTimeMinutes
        self.metadata = metadata
    }

    /// Combines merchant configuration and this request for the network layer.
    /// A blank or missing `reference` is replaced with a freshly generated one.
    public func toPaymentParams(config: MoolreConfig) throws -> PaymentParams {
        try PaymentParams(
            amount: amount,
            environment: config.environment,
            apiUser: config.apiUser,
            publicKey: config.publicKey,
            accountNumber: config.accountNumber,
            currency: currency,
            email: email,
            reference: reference.flatMap { $0.isBlank ? nil : $0 } ?? MoolreReferenceGenerator.generate(),
            callback: webhookURL ?? config.webhookURL,
            redirect: redirectURL ?? config.redirectURL,
            reusable: reusable,
            expirationTimeMinutes: expirationTimeMinutes,
            metadata: metadata
        )
    }
}

/// Generates collision-resistant external references for payment attempts.
public enum MoolreReferenceGenerator {
    public static func generate() -> String { "moolre-\(UUID().uuidString.lowercased())" }
}

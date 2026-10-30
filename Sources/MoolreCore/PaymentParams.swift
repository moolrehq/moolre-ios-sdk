import Foundation

/// Validated payment parameters sent to the network layer.
///
/// - `amount`: payment amount in major currency units
/// - `publicKey`: merchant public key; may be blank in `.sandbox`
/// - `reference`: unique external reference sent as `externalref`
/// - `callback`: server webhook URL (optional)
/// - `redirect`: in-app redirect URI
public struct PaymentParams: Equatable, Codable, Sendable {
    public let amount: Decimal
    public let environment: MoolreEnvironment
    public let apiUser: String
    public let publicKey: String
    public let accountNumber: String
    public let currency: String
    public let email: String
    public let reference: String
    public let callback: String?
    public let redirect: String
    public let reusable: Bool
    public let expirationTimeMinutes: Int?
    public let metadata: [String: String]

    /// - Throws: `MoolrePaymentError` with code `INVALID_AMOUNT` for a non-positive amount,
    ///   or `INVALID_CONFIG` for any other invalid value.
    public init(
        amount: Decimal,
        environment: MoolreEnvironment,
        apiUser: String,
        publicKey: String,
        accountNumber: String,
        currency: String = "GHS",
        email: String,
        reference: String,
        callback: String? = nil,
        redirect: String,
        reusable: Bool = false,
        expirationTimeMinutes: Int? = nil,
        metadata: [String: String] = [:]
    ) throws {
        guard amount > 0 else {
            throw MoolrePaymentError(code: MoolreErrorCode.invalidAmount, message: "Amount must be greater than 0")
        }
        guard !apiUser.isBlank else { throw MoolrePaymentError.invalidConfig("API user cannot be blank") }
        guard environment == .sandbox || !publicKey.isBlank else {
            throw MoolrePaymentError.invalidConfig("Public key cannot be blank in LIVE")
        }
        guard !accountNumber.isBlank else { throw MoolrePaymentError.invalidConfig("Account number cannot be blank") }
        guard !currency.isBlank else { throw MoolrePaymentError.invalidConfig("Currency cannot be blank") }
        guard !email.isBlank else { throw MoolrePaymentError.invalidConfig("Email cannot be blank") }
        guard !reference.isBlank else { throw MoolrePaymentError.invalidConfig("Reference cannot be blank") }
        guard callback.map({ !$0.isBlank }) ?? true else {
            throw MoolrePaymentError.invalidConfig("Webhook URL cannot be blank")
        }
        guard !redirect.isBlank else { throw MoolrePaymentError.invalidConfig("Redirect URL cannot be blank") }
        guard expirationTimeMinutes.map({ $0 >= 1 }) ?? true else {
            throw MoolrePaymentError.invalidConfig("Expiration time must be at least 1 minute")
        }

        self.amount = amount
        self.environment = environment
        self.apiUser = apiUser
        self.publicKey = publicKey
        self.accountNumber = accountNumber
        self.currency = currency
        self.email = email
        self.reference = reference
        self.callback = callback
        self.redirect = redirect
        self.reusable = reusable
        self.expirationTimeMinutes = expirationTimeMinutes
        self.metadata = metadata
    }
}

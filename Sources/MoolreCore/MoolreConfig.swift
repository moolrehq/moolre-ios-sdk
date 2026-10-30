import Foundation

/// Merchant configuration shared by the UIKit and SwiftUI entry points.
/// A blank public key is permitted only in `.sandbox`.
public struct MoolreConfig: Equatable, Sendable {
    public let environment: MoolreEnvironment
    public let apiUser: String
    public let publicKey: String
    public let accountNumber: String
    public let webhookURL: String?
    public let redirectURL: String

    /// - Throws: `MoolrePaymentError` with code `INVALID_CONFIG` when a required value is blank.
    public init(
        environment: MoolreEnvironment = .sandbox,
        apiUser: String,
        publicKey: String,
        accountNumber: String,
        webhookURL: String? = nil,
        redirectURL: String = MoolreConstants.defaultRedirectURL
    ) throws {
        guard !apiUser.isBlank else { throw MoolrePaymentError.invalidConfig("API user cannot be blank") }
        guard environment == .sandbox || !publicKey.isBlank else {
            throw MoolrePaymentError.invalidConfig("Public key cannot be blank in LIVE")
        }
        guard !accountNumber.isBlank else { throw MoolrePaymentError.invalidConfig("Account number cannot be blank") }
        guard webhookURL.map({ !$0.isBlank }) ?? true else {
            throw MoolrePaymentError.invalidConfig("Webhook URL cannot be blank")
        }
        guard !redirectURL.isBlank else { throw MoolrePaymentError.invalidConfig("Redirect URL cannot be blank") }

        self.environment = environment
        self.apiUser = apiUser
        self.publicKey = publicKey
        self.accountNumber = accountNumber
        self.webhookURL = webhookURL
        self.redirectURL = redirectURL
    }
}

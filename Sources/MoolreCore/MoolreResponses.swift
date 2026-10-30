import Foundation

/// Payment-link response.
///
/// - `authorizationURL`: URL to send the customer to for payment
/// - `reference`: Moolre-generated transaction reference returned by the link API
public struct PaymentResponse: Equatable, Sendable {
    public let authorizationURL: String
    public let reference: String

    public init(authorizationURL: String, reference: String) {
        self.authorizationURL = authorizationURL
        self.reference = reference
    }
}

/// Payment verification response.
///
/// - `status`: API envelope status (1 = request succeeded)
/// - `transactionStatus`: transaction status (1 = payment succeeded)
/// - `reference`: transaction external reference
/// - `amount`: verified amount
/// - `accountNumber`: account credited by the transaction
public struct VerificationResponse: Equatable, Sendable {
    public let status: Int
    public let transactionStatus: Int
    public let reference: String
    public let amount: Decimal
    public let accountNumber: String?
    public let transactionID: String?
    public let timestamp: String?
    public let currency: String?

    public init(
        status: Int,
        transactionStatus: Int? = nil,
        reference: String,
        amount: Decimal,
        accountNumber: String? = nil,
        transactionID: String? = nil,
        timestamp: String? = nil,
        currency: String? = nil
    ) {
        self.status = status
        self.transactionStatus = transactionStatus ?? status
        self.reference = reference
        self.amount = amount
        self.accountNumber = accountNumber
        self.transactionID = transactionID
        self.timestamp = timestamp
        self.currency = currency
    }

    public var isSuccessful: Bool { status == 1 && transactionStatus == 1 }
}

/// A prepared checkout that can be handed to a platform-specific UI layer.
///
/// - `reference`: Moolre-generated transaction reference
/// - `externalReference`: merchant reference sent as `externalref`
public struct MoolreCheckoutSession: Equatable, Sendable {
    public let authorizationURL: String
    public let reference: String
    public let redirectURL: String
    public let externalReference: String?

    public init(
        authorizationURL: String,
        reference: String,
        redirectURL: String,
        externalReference: String? = nil
    ) throws {
        guard !authorizationURL.isBlank else { throw MoolrePaymentError.invalidConfig("Authorization URL cannot be blank") }
        guard !reference.isBlank else { throw MoolrePaymentError.invalidConfig("Reference cannot be blank") }
        guard !redirectURL.isBlank else { throw MoolrePaymentError.invalidConfig("Redirect URL cannot be blank") }
        guard externalReference.map({ !$0.isBlank }) ?? true else {
            throw MoolrePaymentError.invalidConfig("External reference cannot be blank")
        }
        self.authorizationURL = authorizationURL
        self.reference = reference
        self.redirectURL = redirectURL
        self.externalReference = externalReference
    }

    /// References the checkout redirect is allowed to carry.
    public var expectedReferences: Set<String> {
        Set([reference, externalReference].compactMap { $0 }.filter { !$0.isBlank })
    }
}

/// Final outcome of a payment attempt.
public enum MoolrePaymentResult: Equatable, Sendable {
    /// The payment was verified successfully.
    case success(reference: String, verification: VerificationResponse)
    /// The customer left checkout before a verified payment was available.
    case cancelled
    /// The payment could not be prepared or verified.
    case failure(code: String, message: String)
}

import Foundation

/// Network boundary used by the payment coordinator and replaceable in tests.
public protocol MoolrePaymentGateway: Sendable {
    func initiatePayment(_ params: PaymentParams) async throws -> PaymentResponse

    func verifyPayment(
        reference: String,
        environment: MoolreEnvironment,
        apiUser: String,
        publicKey: String,
        accountNumber: String
    ) async throws -> VerificationResponse
}

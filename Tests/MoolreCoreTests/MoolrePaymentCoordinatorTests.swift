import XCTest
@testable import MoolreCore

final class MoolrePaymentCoordinatorTests: XCTestCase {

    func testInitiatePaymentMapsGatewayResponseToCheckoutSession() async throws {
        let gateway = FakeGateway(payment: PaymentResponse(authorizationURL: "https://checkout.example/pay", reference: "moolre-ref"))
        let session = try await coordinator(gateway).initiatePayment(params(reference: "ref-123"))

        XCTAssertEqual(session.authorizationURL, "https://checkout.example/pay")
        XCTAssertEqual(session.reference, "moolre-ref")
        XCTAssertEqual(session.externalReference, "ref-123")
        XCTAssertEqual(session.redirectURL, "moolre://payment-callback")
    }

    func testInitiatePaymentPreservesStructuredGatewayFailure() async throws {
        let gateway = FakeGateway(initiationError: MoolrePaymentError(code: "DECLINED", message: "Declined"))
        do {
            _ = try await coordinator(gateway).initiatePayment(params())
            XCTFail("Expected failure")
        } catch {
            XCTAssertEqual((error as? MoolrePaymentError)?.code, "DECLINED")
        }
    }

    func testInitiatePaymentMapsUnknownErrorsToInitiationFailed() async throws {
        let gateway = FakeGateway(initiationError: URLError(.badServerResponse))
        do {
            _ = try await coordinator(gateway).initiatePayment(params())
            XCTFail("Expected failure")
        } catch {
            XCTAssertEqual((error as? MoolrePaymentError)?.code, MoolreErrorCode.initiationFailed)
        }
    }

    func testVerifyPaymentReturnsSuccessForVerifiedPayment() async throws {
        let gateway = FakeGateway(verifications: [verification(reference: "ref-123")])
        let result = await coordinator(gateway).verifyPayment(params(reference: "ref-123"), redirectReference: "ref-123")

        guard case .success(let reference, _) = result else { return XCTFail("Expected success, got \(result)") }
        XCTAssertEqual(reference, "ref-123")
    }

    func testVerifyPaymentUsesMerchantReferenceWhenRedirectUsesGatewayReference() async throws {
        let gateway = FakeGateway(verifications: [verification(reference: "merchant-order-42")])
        let result = await coordinator(gateway).verifyPayment(
            params(reference: "merchant-order-42"),
            redirectReference: "moolre-generated-reference"
        )

        guard case .success = result else { return XCTFail("Expected success, got \(result)") }
        XCTAssertEqual(gateway.verifiedReferences, ["merchant-order-42"])
    }

    func testVerifyPaymentIgnoresAmountAndCurrencyWhenStatusAndReferenceMatch() async throws {
        let gateway = FakeGateway(verifications: [
            VerificationResponse(status: 1, reference: "ref-123", amount: 1, currency: "USD")
        ])
        let result = await coordinator(gateway).verifyPayment(params(reference: "ref-123"), redirectReference: "ref-123")

        guard case .success = result else { return XCTFail("Expected success, got \(result)") }
    }

    func testVerifyPaymentReturnsFailureForUnverifiedPayment() async throws {
        let gateway = FakeGateway(verifications: [VerificationResponse(status: 0, reference: "ref-123", amount: 0)])
        let result = await coordinator(gateway).verifyPayment(params(reference: "ref-123"), redirectReference: "ref-123")

        XCTAssertEqual(result.failureCode, MoolreErrorCode.verificationFailed)
    }

    func testVerifyPaymentRetriesPendingTransactionBeforeFailing() async throws {
        let pending = VerificationResponse(status: 1, transactionStatus: 0, reference: "ref-123", amount: 10)
        let gateway = FakeGateway(verifications: [pending, verification(reference: "ref-123")])
        let result = await coordinator(gateway).verifyPayment(params(reference: "ref-123"), redirectReference: "ref-123")

        guard case .success = result else { return XCTFail("Expected success, got \(result)") }
        XCTAssertEqual(gateway.verifiedReferences.count, 2)
    }

    func testVerifyPaymentStopsAfterConfiguredAttempts() async throws {
        let pending = VerificationResponse(status: 1, transactionStatus: 0, reference: "ref-123", amount: 10)
        let gateway = FakeGateway(verifications: [pending, pending, pending, verification(reference: "ref-123")])
        let result = await coordinator(gateway).verifyPayment(params(reference: "ref-123"), redirectReference: "ref-123")

        XCTAssertEqual(result.failureCode, MoolreErrorCode.verificationFailed)
        XCTAssertEqual(gateway.verifiedReferences.count, 3)
    }

    func testVerifyPaymentAttemptsOverrideKeepsCheckingPendingTransaction() async throws {
        let pending = VerificationResponse(status: 1, transactionStatus: 0, reference: "ref-123", amount: 10)
        let gateway = FakeGateway(verifications: [pending, pending, pending, verification(reference: "ref-123")])
        let result = await coordinator(gateway).verifyPayment(
            reference: "ref-123",
            environment: .sandbox,
            apiUser: "api-user",
            publicKey: "",
            accountNumber: "account",
            attempts: 10
        )

        guard case .success = result else { return XCTFail("Expected success, got \(result)") }
        XCTAssertEqual(gateway.verifiedReferences.count, 4)
    }

    func testVerifyPaymentReturnsFailureForMismatchedVerifiedReference() async throws {
        let gateway = FakeGateway(verifications: [verification(reference: "someone-else")])
        let result = await coordinator(gateway).verifyPayment(params(reference: "ref-123"), redirectReference: "ref-123")

        XCTAssertEqual(result.failureCode, MoolreErrorCode.referenceMismatch)
    }

    func testVerifyPaymentRejectsBlankReference() async throws {
        let result = await coordinator(FakeGateway()).verifyPayment(params(), redirectReference: "  ")

        XCTAssertEqual(result.failureCode, MoolreErrorCode.missingReference)
    }

    // MARK: - Request mapping

    func testRequestMapsMerchantConfigAndPaymentValues() throws {
        let params = try MoolrePaymentRequest(amount: Decimal(string: "42.50")!, email: "customer@example.com", reference: "order-42")
            .toPaymentParams(config: config())

        XCTAssertEqual(params.amount, Decimal(string: "42.50"))
        XCTAssertEqual(params.publicKey, "public-key")
        XCTAssertEqual(params.accountNumber, "account-number")
        XCTAssertEqual(params.currency, "GHS")
        XCTAssertEqual(params.reference, "order-42")
        XCTAssertEqual(params.callback, "https://example.com/webhook")
        XCTAssertEqual(params.redirect, "moolre://payment-callback")
    }

    func testRequestWebhookAndRedirectOverrideMerchantDefaults() throws {
        let params = try MoolrePaymentRequest(
            amount: 10,
            email: "customer@example.com",
            webhookURL: "https://example.com/custom-webhook",
            redirectURL: "moolre://custom-callback"
        ).toPaymentParams(config: config())

        XCTAssertEqual(params.callback, "https://example.com/custom-webhook")
        XCTAssertEqual(params.redirect, "moolre://custom-callback")
    }

    func testRequestGeneratesANewReferenceForEveryConversionWhenOmitted() throws {
        let request = MoolrePaymentRequest(amount: 10, email: "customer@example.com", reference: " ")
        let first = try request.toPaymentParams(config: config()).reference
        let second = try request.toPaymentParams(config: config()).reference

        XCTAssertTrue(first.hasPrefix("moolre-"))
        XCTAssertTrue(second.hasPrefix("moolre-"))
        XCTAssertNotEqual(first, second)
    }

    func testSandboxConfigAcceptsBlankPublicKey() throws {
        let config = try MoolreConfig(environment: .sandbox, apiUser: "user", publicKey: "", accountNumber: "account")
        let params = try MoolrePaymentRequest(amount: 10, email: "customer@example.com").toPaymentParams(config: config)

        XCTAssertEqual(params.publicKey, "")
        XCTAssertEqual(params.environment, .sandbox)
    }

    // MARK: - Helpers

    private func coordinator(_ gateway: FakeGateway) -> MoolrePaymentCoordinator {
        MoolrePaymentCoordinator(gateway: gateway, verificationAttempts: 3, verificationDelay: 0)
    }

    private func config() throws -> MoolreConfig {
        try MoolreConfig(
            environment: .sandbox,
            apiUser: "api-user",
            publicKey: "public-key",
            accountNumber: "account-number",
            webhookURL: "https://example.com/webhook"
        )
    }

    private func params(reference: String = "ref-123") -> PaymentParams {
        try! PaymentParams(
            amount: 10,
            environment: .sandbox,
            apiUser: "api-user",
            publicKey: "public-key",
            accountNumber: "account-number",
            email: "customer@example.com",
            reference: reference,
            redirect: "moolre://payment-callback"
        )
    }

    private func verification(reference: String) -> VerificationResponse {
        VerificationResponse(status: 1, transactionStatus: 1, reference: reference, amount: 10)
    }
}

extension MoolrePaymentResult {
    var failureCode: String? {
        if case .failure(let code, _) = self { return code }
        return nil
    }
}

private final class FakeGateway: MoolrePaymentGateway, @unchecked Sendable {
    private let lock = NSLock()
    private let payment: PaymentResponse
    private let initiationError: Error?
    private var verifications: [VerificationResponse]
    private(set) var verifiedReferences: [String] = []

    init(
        payment: PaymentResponse = PaymentResponse(authorizationURL: "https://checkout.example/pay", reference: "moolre-ref"),
        initiationError: Error? = nil,
        verifications: [VerificationResponse] = []
    ) {
        self.payment = payment
        self.initiationError = initiationError
        self.verifications = verifications
    }

    func initiatePayment(_ params: PaymentParams) async throws -> PaymentResponse {
        if let initiationError { throw initiationError }
        return payment
    }

    func verifyPayment(
        reference: String,
        environment: MoolreEnvironment,
        apiUser: String,
        publicKey: String,
        accountNumber: String
    ) async throws -> VerificationResponse {
        recordVerification(reference)
    }

    private func recordVerification(_ reference: String) -> VerificationResponse {
        lock.lock()
        defer { lock.unlock() }
        verifiedReferences.append(reference)
        return verifications.count > 1 ? verifications.removeFirst() : verifications[0]
    }
}

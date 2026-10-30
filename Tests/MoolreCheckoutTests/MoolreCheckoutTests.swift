import XCTest
@testable import MoolreCheckout
import MoolreCore

final class MoolreCheckoutRequestTests: XCTestCase {

    func testRejectsNonHTTPSCheckoutURL() {
        XCTAssertThrowsError(try MoolreCheckoutRequest(session: session(authorizationURL: "http://checkout.example/pay"))) { error in
            XCTAssertEqual((error as? MoolrePaymentError)?.code, MoolreErrorCode.invalidCheckoutURL)
        }
    }

    func testRejectsRedirectWithoutHost() {
        XCTAssertThrowsError(try MoolreCheckoutRequest(session: session(redirectURL: "moolre:"))) { error in
            XCTAssertEqual((error as? MoolrePaymentError)?.code, MoolreErrorCode.invalidRedirectURL)
        }
    }

    func testCompletesWithMerchantOrGatewayReference() throws {
        let request = try MoolreCheckoutRequest(session: session())

        XCTAssertEqual(request.callbackScheme, "moolre")
        XCTAssertEqual(
            request.result(forCallback: URL(string: "moolre://payment-callback?reference=order-42")!),
            .completed(reference: "order-42")
        )
        XCTAssertEqual(
            request.result(forCallback: URL(string: "MOOLRE://Payment-Callback?status=1&reference=moolre-ref")!),
            .completed(reference: "moolre-ref")
        )
    }

    func testRejectsMissingReference() throws {
        let request = try MoolreCheckoutRequest(session: session())

        XCTAssertEqual(
            request.result(forCallback: URL(string: "moolre://payment-callback?reference=")!),
            .failed(code: MoolreErrorCode.missingReference, message: "Payment reference not found in checkout redirect.")
        )
    }

    func testRejectsUnexpectedReference() throws {
        let request = try MoolreCheckoutRequest(session: session())
        let result = request.result(forCallback: URL(string: "moolre://payment-callback?reference=spoofed")!)

        guard case .failed(let code, _) = result else { return XCTFail("Expected failure, got \(result)") }
        XCTAssertEqual(code, MoolreErrorCode.referenceMismatch)
    }

    func testRejectsRedirectWithDifferentHostPortOrPath() throws {
        let request = try MoolreCheckoutRequest(session: session())
        for url in [
            "moolre://other-host?reference=order-42",
            "moolre://payment-callback:8080?reference=order-42",
            "moolre://payment-callback/extra?reference=order-42"
        ] {
            let result = request.result(forCallback: URL(string: url)!)
            guard case .failed(let code, _) = result else { return XCTFail("Expected failure for \(url)") }
            XCTAssertEqual(code, MoolreErrorCode.unsupportedRedirect, url)
        }
    }

    private func session(
        authorizationURL: String = "https://checkout.example/pay",
        redirectURL: String = "moolre://payment-callback"
    ) -> MoolreCheckoutSession {
        try! MoolreCheckoutSession(
            authorizationURL: authorizationURL,
            reference: "moolre-ref",
            redirectURL: redirectURL,
            externalReference: "order-42"
        )
    }
}

@MainActor
final class MoolrePaymentLauncherTests: XCTestCase {

    func testSuccessfulCheckoutIsVerifiedWithMerchantReference() async throws {
        let gateway = ScriptedGateway(verificationReference: "order-42")
        let checkout = FakeCheckout(results: [.completed(reference: "moolre-ref")])
        let launcher = makeLauncher(gateway, checkout)

        let result = await launcher.launch(request(reference: "order-42"), config: try config())

        guard case .success(let reference, _) = result else { return XCTFail("Expected success, got \(result)") }
        XCTAssertEqual(reference, "order-42")
        XCTAssertEqual(checkout.presented.first?.expectedReferences, ["order-42", "moolre-ref"])
        XCTAssertFalse(launcher.isProcessing)
    }

    func testCancelledUnpaidCheckoutIsReportedAsCancelled() async throws {
        let launcher = makeLauncher(ScriptedGateway(transactionStatus: 0), FakeCheckout(results: [.cancelled]))

        let result = await launcher.launch(request(), config: try config())

        XCTAssertEqual(result, .cancelled)
    }

    func testCancelledCheckoutThatWasPaidIsReportedAsSuccess() async throws {
        let launcher = makeLauncher(ScriptedGateway(), FakeCheckout(results: [.cancelled]))

        let result = await launcher.launch(request(reference: "order-42"), config: try config())

        guard case .success(let reference, _) = result else { return XCTFail("Expected success, got \(result)") }
        XCTAssertEqual(reference, "order-42")
    }

    func testCheckoutIsClosedOncePaymentIsConfirmed() async throws {
        let checkout = FakeCheckout(results: [], waitsForCancel: true)
        let launcher = makeLauncher(ScriptedGateway(), checkout)
        launcher.statusPollInterval = 0.01

        let result = await launcher.launch(request(reference: "order-42"), config: try config())

        guard case .success(let reference, _) = result else { return XCTFail("Expected success, got \(result)") }
        XCTAssertEqual(reference, "order-42")
        XCTAssertEqual(checkout.cancelCount, 1)
    }

    func testCheckoutStaysOpenWhilePaymentIsUnconfirmed() async throws {
        let checkout = FakeCheckout(results: [.cancelled], waitsForCancel: false, presentDelay: 0.1)
        let launcher = makeLauncher(ScriptedGateway(transactionStatus: 0), checkout)
        launcher.statusPollInterval = 0.01

        let result = await launcher.launch(request(), config: try config())

        XCTAssertEqual(result, .cancelled)
        XCTAssertEqual(checkout.cancelCount, 0)
    }

    func testCheckoutFailureIsPassedThrough() async throws {
        let failure = MoolreCheckoutResult.failed(code: MoolreErrorCode.referenceMismatch, message: "mismatch")
        let launcher = makeLauncher(ScriptedGateway(), FakeCheckout(results: [failure]))

        let result = await launcher.launch(request(), config: try config())

        XCTAssertEqual(result, .failure(code: MoolreErrorCode.referenceMismatch, message: "mismatch"))
    }

    func testGeneratedReferenceIsReusedAfterInitiationFailureAndClearedAfterCheckout() async throws {
        let gateway = ScriptedGateway(initiationFailures: 1)
        let checkout = FakeCheckout(results: [.cancelled, .cancelled])
        let launcher = makeLauncher(gateway, checkout)

        let first = await launcher.launch(request(), config: try config())
        XCTAssertEqual(first.failureCode, "NETWORK_OR_UNKNOWN_ERROR")
        _ = await launcher.launch(request(), config: try config())
        _ = await launcher.launch(request(), config: try config())

        XCTAssertEqual(gateway.initiatedReferences.count, 3)
        XCTAssertTrue(gateway.initiatedReferences[0].hasPrefix("moolre-"))
        XCTAssertEqual(gateway.initiatedReferences[0], gateway.initiatedReferences[1])
        XCTAssertNotEqual(gateway.initiatedReferences[1], gateway.initiatedReferences[2])
    }

    func testInvalidAmountFailsBeforeInitiation() async throws {
        let gateway = ScriptedGateway()
        let launcher = makeLauncher(gateway, FakeCheckout(results: []))

        let result = await launcher.launch(MoolrePaymentRequest(amount: 0, email: "customer@example.com"), config: try config())

        XCTAssertEqual(result.failureCode, MoolreErrorCode.invalidAmount)
        XCTAssertTrue(gateway.initiatedReferences.isEmpty)
    }

    private func makeLauncher(_ gateway: ScriptedGateway, _ checkout: FakeCheckout) -> MoolrePaymentLauncher {
        MoolrePaymentLauncher(
            coordinator: MoolrePaymentCoordinator(gateway: gateway, verificationAttempts: 1, verificationDelay: 0),
            checkout: checkout
        )
    }

    private func config() throws -> MoolreConfig {
        try MoolreConfig(environment: .sandbox, apiUser: "api-user", publicKey: "", accountNumber: "account")
    }

    private func request(reference: String? = nil) -> MoolrePaymentRequest {
        MoolrePaymentRequest(amount: Decimal(string: "25.00")!, email: "customer@example.com", reference: reference)
    }
}

private extension MoolrePaymentResult {
    var failureCode: String? {
        if case .failure(let code, _) = self { return code }
        return nil
    }
}

@MainActor
private final class FakeCheckout: MoolreCheckoutPresenting {
    private var results: [MoolreCheckoutResult]
    private let waitsForCancel: Bool
    private let presentDelay: TimeInterval
    private var pending: CheckedContinuation<MoolreCheckoutResult, Never>?
    private(set) var presented: [MoolreCheckoutSession] = []
    private(set) var cancelCount = 0

    /// `waitsForCancel` keeps checkout open until `cancel()`, like a customer who never closes it.
    init(results: [MoolreCheckoutResult], waitsForCancel: Bool = false, presentDelay: TimeInterval = 0) {
        self.results = results
        self.waitsForCancel = waitsForCancel
        self.presentDelay = presentDelay
    }

    func present(_ session: MoolreCheckoutSession) async -> MoolreCheckoutResult {
        presented.append(session)
        if waitsForCancel {
            return await withCheckedContinuation { pending = $0 }
        }
        if presentDelay > 0 {
            try? await Task.sleep(nanoseconds: UInt64(presentDelay * 1_000_000_000))
        }
        return results.removeFirst()
    }

    func cancel() {
        cancelCount += 1
        pending?.resume(returning: .cancelled)
        pending = nil
    }
}

private final class ScriptedGateway: MoolrePaymentGateway, @unchecked Sendable {
    private let lock = NSLock()
    private var initiationFailures: Int
    private let verificationReference: String?
    private let transactionStatus: Int
    private(set) var initiatedReferences: [String] = []

    init(initiationFailures: Int = 0, verificationReference: String? = nil, transactionStatus: Int = 1) {
        self.initiationFailures = initiationFailures
        self.verificationReference = verificationReference
        self.transactionStatus = transactionStatus
    }

    func initiatePayment(_ params: PaymentParams) async throws -> PaymentResponse {
        try recordInitiation(params)
    }

    private func recordInitiation(_ params: PaymentParams) throws -> PaymentResponse {
        lock.lock()
        defer { lock.unlock() }
        initiatedReferences.append(params.reference)
        if initiationFailures > 0 {
            initiationFailures -= 1
            throw MoolrePaymentError(code: "NETWORK_OR_UNKNOWN_ERROR", message: "offline")
        }
        return PaymentResponse(authorizationURL: "https://checkout.example/pay", reference: "moolre-ref")
    }

    func verifyPayment(
        reference: String,
        environment: MoolreEnvironment,
        apiUser: String,
        publicKey: String,
        accountNumber: String
    ) async throws -> VerificationResponse {
        VerificationResponse(status: 1, transactionStatus: transactionStatus, reference: verificationReference ?? reference, amount: 25)
    }
}

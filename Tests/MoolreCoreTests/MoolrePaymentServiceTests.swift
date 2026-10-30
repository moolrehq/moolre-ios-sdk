import XCTest
@testable import MoolreCore

final class MoolrePaymentServiceTests: XCTestCase {

    func testInitiatePaymentUsesSandboxContract() throws {
        let request = try MoolrePaymentService().buildInitiationRequest(paymentParams())

        XCTAssertEqual(request.url?.absoluteString, "https://sandbox.moolre.com/embed/link")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-API-USER"), "sandbox-user")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-API-PUBKEY"), "public-key")

        let body = try requestBody(request)
        XCTAssertEqual(body["type"] as? Int, 1)
        XCTAssertEqual(body["amount"] as? String, "12.5")
        XCTAssertEqual(body["email"] as? String, "customer@example.com")
        XCTAssertEqual(body["externalref"] as? String, "order-123")
        XCTAssertEqual(body["reusable"] as? String, "0")
        XCTAssertEqual(body["currency"] as? String, "GHS")
        XCTAssertEqual(body["accountnumber"] as? String, "1234567890")
        XCTAssertEqual(body["redirect"] as? String, "moolre://payment-callback")
        XCTAssertEqual(body["callback"] as? String, "https://example.com/webhook")
        XCTAssertEqual(body["expiration_time"] as? Int, 15)
        XCTAssertEqual(body["metadata"] as? [String: String], ["order_id": "42"])
    }

    func testLiveInitiationOmitsNonHTTPSRedirect() throws {
        let body = try requestBody(MoolrePaymentService().buildInitiationRequest(paymentParams(environment: .live)))

        XCTAssertNil(body["redirect"])
    }

    func testVerifyPaymentUsesSandboxStatusContract() throws {
        let request = try MoolrePaymentService().buildVerificationRequest(
            reference: "order-123",
            environment: .sandbox,
            apiUser: "sandbox-user",
            publicKey: "public-key",
            accountNumber: "1234567890"
        )

        XCTAssertEqual(request.url?.absoluteString, "https://sandbox.moolre.com/open/transact/status")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-API-USER"), "sandbox-user")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-API-PUBKEY"), "public-key")
        let body = try requestBody(request)
        XCTAssertEqual(body["type"] as? Int, 1)
        XCTAssertEqual(body["idtype"] as? Int, 1)
        XCTAssertEqual(body["id"] as? String, "order-123")
        XCTAssertEqual(body["accountnumber"] as? String, "1234567890")
    }

    func testLiveEnvironmentUsesLiveEndpoints() throws {
        let service = MoolrePaymentService()
        let initiation = try service.buildInitiationRequest(paymentParams(environment: .live))
        let verification = try service.buildVerificationRequest(
            reference: "order-123", environment: .live, apiUser: "user", publicKey: "key", accountNumber: "account"
        )
        XCTAssertEqual(initiation.url?.absoluteString, "https://api.moolre.com/embed/link")
        XCTAssertEqual(verification.url?.absoluteString, "https://api.moolre.com/open/transact/status")
    }

    func testSandboxAcceptsBlankPublicKeyAndOmitsHeaderForBothOperations() throws {
        let service = MoolrePaymentService()
        let initiation = try service.buildInitiationRequest(paymentParams(publicKey: ""))
        let verification = try service.buildVerificationRequest(
            reference: "order-123", environment: .sandbox, apiUser: "sandbox-user", publicKey: "  ", accountNumber: "1234567890"
        )
        XCTAssertNil(initiation.value(forHTTPHeaderField: "X-API-PUBKEY"))
        XCTAssertNil(verification.value(forHTTPHeaderField: "X-API-PUBKEY"))
        XCTAssertEqual(initiation.value(forHTTPHeaderField: "X-API-USER"), "sandbox-user")
        XCTAssertEqual(verification.value(forHTTPHeaderField: "X-API-USER"), "sandbox-user")
    }

    func testLiveRejectsBlankPublicKeyInConfigParamsAndDirectVerification() {
        expectInvalid { _ = try MoolreConfig(environment: .live, apiUser: "user", publicKey: "", accountNumber: "account") }
        expectInvalid { _ = try self.paymentParams(environment: .live, publicKey: " ") }
        expectInvalid {
            _ = try MoolrePaymentService().buildVerificationRequest(
                reference: "order-123", environment: .live, apiUser: "user", publicKey: "", accountNumber: "account"
            )
        }
    }

    func testBothEnvironmentsStillRequireAPIUserAndAccountNumber() {
        for environment in MoolreEnvironment.allCases {
            expectInvalid { _ = try MoolreConfig(environment: environment, apiUser: "", publicKey: "key", accountNumber: "account") }
            expectInvalid { _ = try MoolreConfig(environment: environment, apiUser: "user", publicKey: "key", accountNumber: "") }
            expectInvalid { _ = try self.paymentParams(environment: environment, apiUser: "") }
            expectInvalid { _ = try self.paymentParams(environment: environment, accountNumber: "") }
            expectInvalid {
                _ = try MoolrePaymentService().buildVerificationRequest(
                    reference: "order-123", environment: environment, apiUser: "", publicKey: "key", accountNumber: "account"
                )
            }
        }
    }

    func testNonPositiveAmountIsReportedAsInvalidAmount() {
        for amount: Decimal in [0, -1] {
            XCTAssertThrowsError(try paymentParams(amount: amount)) { error in
                XCTAssertEqual((error as? MoolrePaymentError)?.code, MoolreErrorCode.invalidAmount)
            }
        }
    }

    func testValidAuthenticationErrorsRetainAPICodeMessageAndHTTPStatus() async {
        for verification in [false, true] {
            for status in [200, 401, 403] {
                let error = await failure(authError, status: status, verification: verification)
                XCTAssertEqual(error.code, "AUTH01")
                XCTAssertTrue(error.message.contains("Invalid credentials"))
                XCTAssertTrue(error.message.contains("HTTP Status: \(status)"))
            }
        }
    }

    func testFieldValidationErrorsSurfaceTheirMessages() async {
        let body = #"{"errors":{"redirect":["Redirect must be a public HTTPS URL without credentials or a custom port."]}}"#
        let error = await failure(body, status: 400, verification: false)
        XCTAssertEqual(error.code, "HTTP_400")
        XCTAssertTrue(error.message.contains("Redirect must be a public HTTPS URL"))
        XCTAssertTrue(error.message.contains("HTTP Status: 400"))
    }

    func testPHPDiagnosticsDoNotHideAuthenticationErrorsIncludingHTTP200() async {
        let prefixes = [
            "Warning: Undefined array key in /private/server.php on line 42\n",
            "<br />\n<b>Warning</b>: Undefined array key in <b>/private/server.php</b><br />\n",
            "PHP Notice: Undefined variable in /private/server.php\n"
        ]
        for verification in [false, true] {
            for status in [200, 401] {
                for prefix in prefixes {
                    let error = await failure(prefix + authError, status: status, verification: verification)
                    XCTAssertEqual(error.code, "AUTH01")
                    XCTAssertTrue(error.message.contains("Invalid credentials"))
                    XCTAssertTrue(error.message.contains("HTTP Status: \(status)"))
                    XCTAssertFalse(error.message.contains("/private"))
                }
            }
        }
    }

    func testNonJSONHTTPErrorsKeepHTTPFailureInsteadOfParsingFailure() async {
        for verification in [false, true] {
            for status in [401, 403, 429, 500, 502] {
                for body in ["", "   ", "<html>upstream error</html>", "Warning: failure"] {
                    let error = await failure(body, status: status, verification: verification)
                    XCTAssertEqual(error.code, "HTTP_\(status)")
                    XCTAssertTrue(error.message.contains("HTTP Status: \(status)"))
                }
            }
        }
    }

    func testMalformedSuccessfulResponsesFailWithoutLeakingRawBody() async {
        for verification in [false, true] {
            for body in ["private-response-text", "[]", "\(authError) trailing-private-text"] {
                let error = await failure(body, status: 200, verification: verification)
                XCTAssertEqual(error.code, "JSON_PARSING_ERROR")
                XCTAssertFalse(error.message.contains("private"))
            }
            let empty = await failure("", status: 200, verification: verification)
            XCTAssertEqual(empty.code, "EMPTY_RESPONSE")
        }
    }

    func testPrefixedSuccessAndArbitraryPrefixedErrorsAreNeverAccepted() async {
        for verification in [false, true] {
            let success = verification ? verificationSuccess : initiationSuccess
            let prefixedSuccess = await failure("Warning: diagnostic\n\(success)", status: 200, verification: verification)
            XCTAssertEqual(prefixedSuccess.code, "JSON_PARSING_ERROR")
            let arbitraryPrefix = await failure("arbitrary text\n\(authError)", status: 200, verification: verification)
            XCTAssertEqual(arbitraryPrefix.code, "JSON_PARSING_ERROR")
            let successWithHTTPError = await failure(success, status: 401, verification: verification)
            XCTAssertEqual(successWithHTTPError.code, "HTTP_401")
        }
    }

    func testDuplicateReferenceMappingIsPreserved() async {
        let error = await failure(#"{"status":0,"code":"INP02","message":"Duplicate reference"}"#, status: 200, verification: false)
        XCTAssertEqual(error.code, "DUPLICATE_REFERENCE")
    }

    func testNetworkFailureIsMappedToNetworkError() async {
        let service = MoolrePaymentService(transport: StubTransport { throw URLError(.notConnectedToInternet) })
        do {
            _ = try await service.initiatePayment(paymentParams())
            XCTFail("Expected SDK failure")
        } catch {
            XCTAssertEqual((error as? MoolrePaymentError)?.code, "NETWORK_OR_UNKNOWN_ERROR")
        }
    }

    func testValidInitiationAndVerificationStillSucceed() async throws {
        let payment = try await service(initiationSuccess).initiatePayment(paymentParams())
        XCTAssertEqual(payment.authorizationURL, "https://checkout.example/pay")
        XCTAssertEqual(payment.reference, "generated-reference")

        let verification = try await service(verificationSuccess).verifyPayment(
            reference: "order-123", environment: .sandbox, apiUser: "sandbox-user", publicKey: "", accountNumber: "1234567890"
        )
        XCTAssertEqual(verification.reference, "order-123")
        XCTAssertEqual(verification.amount, Decimal(string: "12.50"))
        XCTAssertEqual(verification.transactionStatus, 1)
        XCTAssertTrue(verification.isSuccessful)
    }

    func testStatusValuesAcceptBooleansAndStrings() async throws {
        let body = #"{"status":true,"data":{"externalref":"order-123","txstatus":"1","amount":12.5}}"#
        let verification = try await service(body).verifyPayment(
            reference: "order-123", environment: .sandbox, apiUser: "sandbox-user", publicKey: "", accountNumber: "1234567890"
        )
        XCTAssertTrue(verification.isSuccessful)
        XCTAssertEqual(verification.amount, Decimal(string: "12.5"))
    }

    // MARK: - Helpers

    private let authError = #"{"status":0,"code":"AUTH01","message":"Invalid credentials"}"#
    private let initiationSuccess = #"{"status":1,"data":{"authorization_url":"https://checkout.example/pay","reference":"generated-reference"}}"#
    private let verificationSuccess = #"{"status":1,"data":{"externalref":"order-123","txstatus":1,"amount":"12.50","accountnumber":"1234567890"}}"#

    private func service(_ body: String, status: Int = 200) -> MoolrePaymentService {
        MoolrePaymentService(transport: StubTransport { (Data(body.utf8), status) })
    }

    private func failure(_ body: String, status: Int, verification: Bool) async -> MoolrePaymentError {
        do {
            if verification {
                _ = try await service(body, status: status).verifyPayment(
                    reference: "order-123", environment: .sandbox, apiUser: "sandbox-user", publicKey: "", accountNumber: "1234567890"
                )
            } else {
                _ = try await service(body, status: status).initiatePayment(paymentParams())
            }
        } catch let error as MoolrePaymentError {
            return error
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        XCTFail("Expected SDK failure for body: \(body)")
        return MoolrePaymentError(code: "", message: "")
    }

    private func expectInvalid(_ block: () throws -> Void, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try block(), file: file, line: line) { error in
            XCTAssertEqual((error as? MoolrePaymentError)?.code, MoolreErrorCode.invalidConfig, file: file, line: line)
        }
    }

    private func paymentParams(
        amount: Decimal = Decimal(string: "12.50")!,
        environment: MoolreEnvironment = .sandbox,
        apiUser: String = "sandbox-user",
        publicKey: String = "public-key",
        accountNumber: String = "1234567890"
    ) throws -> PaymentParams {
        try PaymentParams(
            amount: amount,
            environment: environment,
            apiUser: apiUser,
            publicKey: publicKey,
            accountNumber: accountNumber,
            currency: "GHS",
            email: "customer@example.com",
            reference: "order-123",
            callback: "https://example.com/webhook",
            redirect: "moolre://payment-callback",
            expirationTimeMinutes: 15,
            metadata: ["order_id": "42"]
        )
    }

    private func requestBody(_ request: URLRequest) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
    }
}

private struct StubTransport: MoolreHTTPTransport {
    let respond: @Sendable () throws -> (Data, Int)

    func send(_ request: URLRequest) async throws -> (Data, Int) {
        try respond()
    }
}

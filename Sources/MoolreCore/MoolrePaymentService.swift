import Foundation

/// Sends a prepared request and returns the raw body and HTTP status. Replaceable in tests.
protocol MoolreHTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, Int)
}

private struct URLSessionTransport: MoolreHTTPTransport {
    let session: URLSession

    func send(_ request: URLRequest) async throws -> (Data, Int) {
        let (data, response) = try await session.data(for: request)
        return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
    }
}

/// Default network-backed payment gateway for the Moolre payment-link and status APIs.
public final class MoolrePaymentService: MoolrePaymentGateway {
    private static let mediaType = "application/json"

    private let transport: MoolreHTTPTransport

    public convenience init(session: URLSession = .shared) {
        self.init(transport: URLSessionTransport(session: session))
    }

    init(transport: MoolreHTTPTransport) {
        self.transport = transport
    }

    public func initiatePayment(_ params: PaymentParams) async throws -> PaymentResponse {
        let request = try buildInitiationRequest(params)
        let (data, statusCode) = try await send(request, action: "Payment initiation")
        return try parseInitiationResponse(data: data, statusCode: statusCode)
    }

    public func verifyPayment(
        reference: String,
        environment: MoolreEnvironment,
        apiUser: String,
        publicKey: String,
        accountNumber: String
    ) async throws -> VerificationResponse {
        let request = try buildVerificationRequest(
            reference: reference,
            environment: environment,
            apiUser: apiUser,
            publicKey: publicKey,
            accountNumber: accountNumber
        )
        let (data, statusCode) = try await send(request, action: "Payment verification")
        return try parseVerificationResponse(data: data, statusCode: statusCode)
    }

    // MARK: - Requests

    func buildInitiationRequest(_ params: PaymentParams) throws -> URLRequest {
        var fields: [String: Any] = [
            "type": MoolreConstants.paymentLinkType,
            "amount": NSDecimalNumber(decimal: params.amount).stringValue,
            "email": params.email,
            "externalref": params.reference,
            "reusable": params.reusable ? "1" : "0",
            "currency": params.currency,
            "accountnumber": params.accountNumber
        ]
        // LIVE accepts only public HTTPS redirects; without one, checkout is closed by status polling.
        if params.environment == .sandbox || params.redirect.lowercased().hasPrefix("https://") {
            fields["redirect"] = params.redirect
        }
        if let callback = params.callback { fields["callback"] = callback }
        if let expiration = params.expirationTimeMinutes { fields["expiration_time"] = expiration }
        if !params.metadata.isEmpty { fields["metadata"] = params.metadata }

        return try buildRequest(
            url: params.environment.paymentEndpoint,
            apiUser: params.apiUser,
            publicKey: params.publicKey,
            fields: fields
        )
    }

    func buildVerificationRequest(
        reference: String,
        environment: MoolreEnvironment,
        apiUser: String,
        publicKey: String,
        accountNumber: String
    ) throws -> URLRequest {
        guard !reference.isBlank else { throw MoolrePaymentError.invalidConfig("Reference cannot be blank") }
        guard !apiUser.isBlank else { throw MoolrePaymentError.invalidConfig("API user cannot be blank") }
        guard !accountNumber.isBlank else { throw MoolrePaymentError.invalidConfig("Account number cannot be blank") }
        guard environment == .sandbox || !publicKey.isBlank else {
            throw MoolrePaymentError.invalidConfig("Public key cannot be blank in LIVE")
        }
        return try buildRequest(
            url: environment.statusEndpoint,
            apiUser: apiUser,
            publicKey: publicKey,
            fields: [
                "type": MoolreConstants.paymentLinkType,
                "idtype": MoolreConstants.statusIDTypeExternalReference,
                "id": reference,
                "accountnumber": accountNumber
            ]
        )
    }

    private func buildRequest(url: URL, apiUser: String, publicKey: String, fields: [String: Any]) throws -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(Self.mediaType, forHTTPHeaderField: "Content-Type")
        request.setValue(apiUser, forHTTPHeaderField: "X-API-USER")
        if !publicKey.isBlank {
            request.setValue(publicKey, forHTTPHeaderField: "X-API-PUBKEY")
        }
        request.httpBody = try JSONSerialization.data(
            withJSONObject: fields,
            options: [.sortedKeys, .withoutEscapingSlashes]
        )
        return request
    }

    private func send(_ request: URLRequest, action: String) async throws -> (Data, Int) {
        do {
            return try await transport.send(request)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            throw MoolrePaymentError(
                code: MoolreErrorCode.networkOrUnknownError,
                message: "\(action) failed: \(error.localizedDescription)"
            )
        }
    }

    // MARK: - Responses

    func parseInitiationResponse(data: Data, statusCode: Int) throws -> PaymentResponse {
        let json = try readAPIResponse(data: data, statusCode: statusCode, fallbackCode: MoolreErrorCode.initiationFailed)
        let apiMessage = (json["message"] as? String) ?? "No message from API."
        let rawCode = (json["code"] as? String) ?? MoolreErrorCode.initiationFailed
        let apiCode = rawCode == "INP02" ? MoolreErrorCode.duplicateReference : rawCode

        guard let payload = json["data"] as? [String: Any] else {
            throw MoolrePaymentError(code: apiCode, message: "Successful response but 'data' object is missing: \(apiMessage)")
        }
        let authorizationURL = (payload["authorization_url"] as? String) ?? ""
        let reference = (payload["reference"] as? String) ?? ""
        guard !authorizationURL.isBlank, !reference.isBlank else {
            throw MoolrePaymentError(code: apiCode, message: "Successful response is missing checkout URL or reference: \(apiMessage)")
        }
        return PaymentResponse(authorizationURL: authorizationURL, reference: reference)
    }

    func parseVerificationResponse(data: Data, statusCode: Int) throws -> VerificationResponse {
        let json = try readAPIResponse(data: data, statusCode: statusCode, fallbackCode: MoolreErrorCode.verificationFailed)
        let envelopeStatus = Self.status(json["status"])

        guard let payload = json["data"] as? [String: Any] else {
            throw MoolrePaymentError(code: MoolreErrorCode.verificationFailed, message: "Verification response is missing 'data'.")
        }
        guard let externalReference = Self.string(payload["externalref"]) else {
            throw MoolrePaymentError(code: MoolreErrorCode.missingReference, message: "Verification response is missing 'externalref'.")
        }

        return VerificationResponse(
            status: envelopeStatus,
            transactionStatus: Self.status(payload["txstatus"]),
            reference: externalReference,
            amount: Self.decimal(payload["amount"]) ?? 0,
            accountNumber: Self.string(payload["accountnumber"]),
            transactionID: Self.string(payload["transactionid"]),
            timestamp: Self.string(payload["ts"])
        )
    }

    /// HTTP errors remain HTTP errors even when a proxy or PHP emits a non-JSON body.
    /// Recover only explicit API failures after PHP diagnostics, never a success payload.
    /// Do not include raw response bodies or parser error text in public diagnostics.
    private func readAPIResponse(data: Data, statusCode: Int, fallbackCode: String) throws -> [String: Any] {
        let isSuccessful = (200..<300).contains(statusCode)
        let body = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)

        if let json = Self.parseObject(body) {
            if !isSuccessful || Self.status(json["status"]) != 1 {
                throw Self.apiFailure(json: json, statusCode: statusCode, fallbackCode: fallbackCode)
            }
            return json
        }

        if let objectStart = body.firstIndex(of: "{"), objectStart > body.startIndex {
            let prefix = body[..<objectStart]
                .replacingOccurrences(of: "<[^>]*>", with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let isPHPDiagnostic = prefix.range(
                of: "^(?:PHP\\s+)?(?:Warning|Notice|Deprecated|Fatal error|Parse error):",
                options: [.regularExpression, .caseInsensitive]
            ) != nil
            if isPHPDiagnostic,
               let error = Self.parseObject(String(body[objectStart...])),
               Self.isExplicitFailure(error["status"]) {
                throw Self.apiFailure(json: error, statusCode: statusCode, fallbackCode: fallbackCode)
            }
        }

        let code: String
        if !isSuccessful {
            code = MoolreErrorCode.http(statusCode)
        } else if body.isEmpty {
            code = MoolreErrorCode.emptyResponse
        } else {
            code = MoolreErrorCode.jsonParsingError
        }
        throw MoolrePaymentError(code: code, message: "Invalid API response. HTTP Status: \(statusCode).")
    }

    private static func parseObject(_ body: String) -> [String: Any]? {
        guard !body.isEmpty else { return nil }
        return (try? JSONSerialization.jsonObject(with: Data(body.utf8))) as? [String: Any]
    }

    private static func apiFailure(json: [String: Any], statusCode: Int, fallbackCode: String) -> MoolrePaymentError {
        let isAPIFailure = status(json["status"]) != 1
        let rawCode = isAPIFailure ? string(json["code"]) : nil
        let code: String
        if rawCode == "INP02" {
            code = MoolreErrorCode.duplicateReference
        } else if let rawCode {
            code = rawCode
        } else if !(200..<300).contains(statusCode) {
            code = MoolreErrorCode.http(statusCode)
        } else {
            code = fallbackCode
        }
        let message = isAPIFailure ? string(json["message"]) ?? validationMessage(json["errors"]) : nil
        return MoolrePaymentError(code: code, message: "\(message ?? "API request failed.") HTTP Status: \(statusCode).")
    }

    /// Joins field validation errors shaped like `{"errors": {"field": ["message"]}}`.
    private static func validationMessage(_ value: Any?) -> String? {
        guard let errors = value as? [String: Any] else { return nil }
        let messages = errors.keys.sorted().flatMap { key -> [String] in
            switch errors[key] {
            case let list as [Any]: return list.compactMap { string($0) }
            case let text as String: return [text]
            default: return []
            }
        }
        return messages.isEmpty ? nil : messages.joined(separator: " ")
    }

    private static func isExplicitFailure(_ value: Any?) -> Bool {
        switch value {
        case let number as NSNumber: return number.intValue == 0
        case let text as String: return text == "0" || text.caseInsensitiveCompare("false") == .orderedSame
        default: return false
        }
    }

    private static func status(_ value: Any?) -> Int {
        switch value {
        case let number as NSNumber:
            return number.intValue
        case let text as String:
            if text == "1" || text.caseInsensitiveCompare("true") == .orderedSame { return 1 }
            return Int(text) ?? 0
        default:
            return 0
        }
    }

    private static func string(_ value: Any?) -> String? {
        guard let text = value as? String, !text.isBlank else { return nil }
        return text
    }

    private static func decimal(_ value: Any?) -> Decimal? {
        switch value {
        case let number as NSNumber: return Decimal(string: number.stringValue, locale: Locale(identifier: "en_US_POSIX"))
        case let text as String: return Decimal(string: text, locale: Locale(identifier: "en_US_POSIX"))
        default: return nil
        }
    }
}

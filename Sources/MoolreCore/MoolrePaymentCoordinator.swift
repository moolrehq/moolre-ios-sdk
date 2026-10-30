import Foundation
import os

/// Coordinates payment initiation and verification without depending on a UI toolkit.
public final class MoolrePaymentCoordinator: Sendable {
    private static let logger = Logger(subsystem: "com.moolre.sdk", category: "MoolrePayment")

    private let gateway: MoolrePaymentGateway
    private let verificationAttempts: Int
    private let verificationDelayNanoseconds: UInt64

    public init(
        gateway: MoolrePaymentGateway = MoolrePaymentService(),
        verificationAttempts: Int = 3,
        verificationDelay: TimeInterval = 0.5
    ) {
        precondition(verificationAttempts >= 1, "Verification attempts must be at least 1.")
        precondition(verificationDelay >= 0, "Verification delay cannot be negative.")
        self.gateway = gateway
        self.verificationAttempts = verificationAttempts
        self.verificationDelayNanoseconds = UInt64(verificationDelay * 1_000_000_000)
    }

    /// Creates a payment link and returns the checkout session to present.
    /// - Throws: `MoolrePaymentError`, or `CancellationError` when the task is cancelled.
    public func initiatePayment(_ params: PaymentParams) async throws -> MoolreCheckoutSession {
        do {
            let response = try await gateway.initiatePayment(params)
            #if DEBUG
            Self.logger.notice("initiated externalref=\(params.reference, privacy: .public) moolreRef=\(response.reference, privacy: .public)")
            #endif
            return try MoolreCheckoutSession(
                authorizationURL: response.authorizationURL,
                reference: response.reference,
                redirectURL: params.redirect,
                externalReference: params.reference
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw error.asMoolreError(fallbackCode: MoolreErrorCode.initiationFailed)
        }
    }

    /// Verifies a payment using a successful gateway status and an exact external-reference match.
    /// Amount and currency are intentionally not compared by this V1 client-side check.
    public func verifyPayment(_ params: PaymentParams, redirectReference: String) async -> MoolrePaymentResult {
        guard !redirectReference.isBlank else {
            return .failure(code: MoolreErrorCode.missingReference, message: "Payment reference cannot be blank.")
        }
        return await verifyPayment(
            reference: params.reference,
            environment: params.environment,
            apiUser: params.apiUser,
            publicKey: params.publicKey,
            accountNumber: params.accountNumber
        )
    }

    /// - Parameter attempts: Status checks made while the transaction is pending; defaults to
    ///   the coordinator's `verificationAttempts`.
    public func verifyPayment(
        reference: String,
        environment: MoolreEnvironment,
        apiUser: String,
        publicKey: String,
        accountNumber: String,
        attempts: Int? = nil
    ) async -> MoolrePaymentResult {
        guard !reference.isBlank else {
            return .failure(code: MoolreErrorCode.verificationFailed, message: "Payment reference cannot be blank.")
        }

        do {
            var verification = try await gateway.verifyPayment(
                reference: reference,
                environment: environment,
                apiUser: apiUser,
                publicKey: publicKey,
                accountNumber: accountNumber
            )
            Self.logVerification(verification, attempt: 1)
            for attempt in 2..<(max(attempts ?? verificationAttempts, 1) + 1)
            where verification.status == 1 && verification.transactionStatus != 1 {
                try await Task.sleep(nanoseconds: verificationDelayNanoseconds)
                verification = try await gateway.verifyPayment(
                    reference: reference,
                    environment: environment,
                    apiUser: apiUser,
                    publicKey: publicKey,
                    accountNumber: accountNumber
                )
                Self.logVerification(verification, attempt: attempt)
            }

            if !verification.isSuccessful {
                return .failure(code: MoolreErrorCode.verificationFailed, message: "Payment verification failed.")
            }
            if verification.reference != reference {
                return .failure(
                    code: MoolreErrorCode.referenceMismatch,
                    message: "Verified external reference did not match the payment request."
                )
            }
            return .success(reference: reference, verification: verification)
        } catch is CancellationError {
            return .cancelled
        } catch {
            let mapped = error.asMoolreError(fallbackCode: MoolreErrorCode.verificationFailed)
            #if DEBUG
            Self.logger.notice("verify externalref=\(reference, privacy: .public) error=\(mapped.code, privacy: .public) \(mapped.message, privacy: .public)")
            #endif
            return .failure(code: mapped.code, message: mapped.message)
        }
    }

    private static func logVerification(_ verification: VerificationResponse, attempt: Int) {
        #if DEBUG
        logger.notice("verify attempt=\(attempt) externalref=\(verification.reference, privacy: .public) status=\(verification.status) txstatus=\(verification.transactionStatus)")
        #endif
    }
}

extension Error {
    func asMoolreError(fallbackCode: String) -> MoolrePaymentError {
        self as? MoolrePaymentError ?? MoolrePaymentError(
            code: fallbackCode,
            message: (self as? LocalizedError)?.errorDescription ?? "Payment operation failed."
        )
    }
}

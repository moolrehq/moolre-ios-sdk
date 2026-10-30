import Combine
import Foundation
import MoolreCore
import os

/// Prepares, presents, and verifies one checkout at a time.
///
/// Shared by the UIKit and SwiftUI `MoolrePayButton`s; use it directly to drive checkout from
/// your own UI.
@MainActor
public final class MoolrePaymentLauncher: ObservableObject {
    /// Status checks after checkout is closed without a redirect: about 20 s at the default delay.
    static let dismissedCheckoutVerificationAttempts = 40
    /// How often payment status is checked while checkout is open; success closes checkout.
    var statusPollInterval: TimeInterval = 3
    private static let logger = Logger(subsystem: "com.moolre.sdk", category: "MoolrePayment")

    @Published public private(set) var isProcessing = false

    private let coordinator: MoolrePaymentCoordinator
    private let checkout: MoolreCheckoutPresenting

    /// SDK-generated reference reused when a transient initiation failure is retried.
    /// Cleared once checkout returns a result.
    private var retryReference: String?

    public init(
        coordinator: MoolrePaymentCoordinator = MoolrePaymentCoordinator(),
        checkout: MoolreCheckoutPresenting
    ) {
        self.coordinator = coordinator
        self.checkout = checkout
    }

    #if os(iOS)
    public convenience init(coordinator: MoolrePaymentCoordinator = MoolrePaymentCoordinator()) {
        self.init(coordinator: coordinator, checkout: MoolreWebCheckout())
    }
    #endif

    /// Starts payment preparation, presents checkout, and verifies the redirect reference.
    public func launch(_ request: MoolrePaymentRequest, config: MoolreConfig) async -> MoolrePaymentResult {
        guard !isProcessing else {
            return .failure(code: MoolreErrorCode.paymentInProgress, message: "A payment is already in progress.")
        }

        var request = request
        if request.reference.map({ $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) ?? true {
            request.reference = retryReference ?? MoolreReferenceGenerator.generate()
        }
        let params: PaymentParams
        do {
            params = try request.toPaymentParams(config: config)
        } catch {
            let mapped = error as? MoolrePaymentError
            return .failure(
                code: mapped?.code ?? MoolreErrorCode.invalidConfig,
                message: mapped?.message ?? "Payment request is invalid."
            )
        }

        retryReference = params.reference
        isProcessing = true
        defer { isProcessing = false }

        let session: MoolreCheckoutSession
        do {
            session = try await coordinator.initiatePayment(params)
        } catch is CancellationError {
            return .cancelled
        } catch {
            let mapped = error as? MoolrePaymentError
            return .failure(
                code: mapped?.code ?? MoolreErrorCode.initiationFailed,
                message: mapped?.message ?? "Payment initiation failed."
            )
        }

        let statusWatcher = watchForPayment(params)
        let checkoutResult = await checkout.present(session)
        statusWatcher.cancel()
        retryReference = nil
        #if DEBUG
        Self.logger.notice("checkout ended externalref=\(params.reference, privacy: .public) result=\(String(describing: checkoutResult), privacy: .public)")
        #endif

        switch checkoutResult {
        case .completed(let reference):
            return await coordinator.verifyPayment(params, redirectReference: reference)
        case .cancelled:
            // Checkout can be closed after paying, e.g. when an HTTPS redirect is not intercepted,
            // so report success only if the gateway confirms the payment. A pending mobile-money
            // approval can take several seconds; an unknown transaction stops checking at once.
            let verification = await coordinator.verifyPayment(
                reference: params.reference,
                environment: params.environment,
                apiUser: params.apiUser,
                publicKey: params.publicKey,
                accountNumber: params.accountNumber,
                attempts: Self.dismissedCheckoutVerificationAttempts
            )
            if case .success = verification { return verification }
            #if DEBUG
            Self.logger.notice("closed checkout not verified externalref=\(params.reference, privacy: .public) result=\(String(describing: verification), privacy: .public)")
            #endif
            return .cancelled
        case .failed(let code, let message):
            return .failure(code: code, message: message)
        }
    }

    /// Closes checkout once the gateway reports the payment successful, so checkout finishes
    /// even when the redirect cannot be intercepted or is not sent (LIVE requires HTTPS).
    /// Closing reports `.cancelled`, which `launch` then verifies.
    private func watchForPayment(_ params: PaymentParams) -> Task<Void, Never> {
        let interval = UInt64(statusPollInterval * 1_000_000_000)
        return Task { [coordinator, checkout] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: interval)
                guard !Task.isCancelled else { return }
                let result = await coordinator.verifyPayment(
                    reference: params.reference,
                    environment: params.environment,
                    apiUser: params.apiUser,
                    publicKey: params.publicKey,
                    accountNumber: params.accountNumber,
                    attempts: 1
                )
                if case .success = result, !Task.isCancelled {
                    #if DEBUG
                    Self.logger.notice("payment confirmed while checkout open externalref=\(params.reference, privacy: .public); closing checkout")
                    #endif
                    checkout.cancel()
                    return
                }
            }
        }
    }

    /// Completion-handler variant of `launch(_:config:)`. `completion` runs on the main actor.
    public func launch(
        _ request: MoolrePaymentRequest,
        config: MoolreConfig,
        completion: @escaping @MainActor (MoolrePaymentResult) -> Void
    ) {
        Task { @MainActor in
            completion(await launch(request, config: config))
        }
    }
}

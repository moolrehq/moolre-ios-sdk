import Foundation
import MoolreCore

/// Presents a prepared checkout session and reports how it ended.
@MainActor
public protocol MoolreCheckoutPresenting: AnyObject {
    func present(_ session: MoolreCheckoutSession) async -> MoolreCheckoutResult
    /// Closes checkout in progress; the pending `present` call returns `.cancelled`.
    func cancel()
}

#if os(iOS)
import AuthenticationServices
import UIKit
import os

/// Presents checkout in an `ASWebAuthenticationSession` and catches the payment redirect.
///
/// The system browser sheet is used rather than an embedded `WKWebView` so checkout runs with
/// the user's real browser engine and the host app never sees card or wallet input. The session
/// intercepts the redirect scheme itself, so no URL scheme needs to be registered in Info.plist.
@MainActor
public final class MoolreWebCheckout: NSObject, MoolreCheckoutPresenting {
    private static let logger = Logger(subsystem: "com.moolre.sdk", category: "MoolreCheckout")

    /// When `true`, checkout does not share cookies or website data with Safari.
    public var prefersEphemeralWebBrowserSession: Bool

    private let anchorProvider: () -> ASPresentationAnchor?
    private var activeSession: ASWebAuthenticationSession?
    /// Resumes the pending `present` call; set while checkout is shown.
    private var finishActive: ((MoolreCheckoutResult) -> Void)?

    /// - Parameter presentationAnchor: Window to present over. Defaults to the key window of the
    ///   foreground scene.
    public init(
        prefersEphemeralWebBrowserSession: Bool = false,
        presentationAnchor: (() -> ASPresentationAnchor?)? = nil
    ) {
        self.prefersEphemeralWebBrowserSession = prefersEphemeralWebBrowserSession
        self.anchorProvider = presentationAnchor ?? MoolreWebCheckout.keyWindow
        super.init()
    }

    public func present(_ session: MoolreCheckoutSession) async -> MoolreCheckoutResult {
        guard activeSession == nil else {
            return .failed(code: MoolreErrorCode.launchFailed, message: "Checkout is already being presented.")
        }
        let request: MoolreCheckoutRequest
        do {
            request = try MoolreCheckoutRequest(session: session)
        } catch {
            let mapped = error as? MoolrePaymentError
            return .failed(
                code: mapped?.code ?? MoolreErrorCode.invalidCheckoutURL,
                message: mapped?.message ?? "Checkout could not be prepared."
            )
        }

        #if DEBUG
        Self.logger.debug("authorization_url=\(request.checkoutURL.absoluteString, privacy: .private)")
        #endif

        return await withCheckedContinuation { continuation in
            var resumed = false
            let finish: @MainActor (MoolreCheckoutResult) -> Void = { [weak self] result in
                guard !resumed else { return }
                resumed = true
                self?.activeSession = nil
                self?.finishActive = nil
                continuation.resume(returning: result)
            }
            finishActive = finish
            @MainActor func start(interceptsHTTPS: Bool) {
                let completion: (URL?, Error?) -> Void = { url, error in
                    #if DEBUG
                    Self.logger.notice("session ended callback=\(url?.absoluteString ?? "nil", privacy: .public) error=\(String(describing: error), privacy: .public)")
                    #endif
                    Task { @MainActor in
                        // Without Associated Domains for the redirect host, iOS refuses the HTTPS
                        // callback before showing checkout. Reopen without intercepting; the
                        // customer closes checkout and the launcher verifies with the gateway.
                        if interceptsHTTPS, Self.isMissingAssociatedDomain(error) {
                            self.activeSession = nil
                            start(interceptsHTTPS: false)
                            return
                        }
                        finish(Self.result(for: request, callbackURL: url, error: error))
                    }
                }

                let authSession = makeSession(for: request, interceptsHTTPS: interceptsHTTPS, completion: completion)
                authSession.presentationContextProvider = self
                authSession.prefersEphemeralWebBrowserSession = prefersEphemeralWebBrowserSession
                activeSession = authSession
                if !authSession.start() {
                    finish(.failed(code: MoolreErrorCode.launchFailed, message: "Could not open payment checkout."))
                }
            }
            start(interceptsHTTPS: true)
        }
    }

    /// Cancels an in-flight checkout. The pending `present` call returns `.cancelled`.
    public func cancel() {
        activeSession?.cancel()
        // `ASWebAuthenticationSession.cancel()` dismisses checkout without calling the
        // completion handler, so finish the pending `present` call here.
        finishActive?(.cancelled)
    }

    /// An HTTPS redirect is intercepted only on iOS 17.4+ and when `interceptsHTTPS` is set;
    /// otherwise the session waits on a scheme checkout never opens, until the customer closes it.
    private func makeSession(
        for request: MoolreCheckoutRequest,
        interceptsHTTPS: Bool,
        completion: @escaping (URL?, Error?) -> Void
    ) -> ASWebAuthenticationSession {
        let isHTTPS = request.callbackScheme == "https"
        if #available(iOS 17.4, *), isHTTPS, interceptsHTTPS {
            return ASWebAuthenticationSession(
                url: request.checkoutURL,
                callback: .https(host: request.redirectURL.host!, path: request.redirectURL.path),
                completionHandler: completion
            )
        }
        return ASWebAuthenticationSession(
            url: request.checkoutURL,
            callbackURLScheme: isHTTPS ? Self.unhandledCallbackScheme : request.callbackScheme,
            completionHandler: completion
        )
    }

    private static let unhandledCallbackScheme = "moolre-checkout-closed"

    private static func isMissingAssociatedDomain(_ error: Error?) -> Bool {
        guard let error = error as NSError?,
              error.domain == ASWebAuthenticationSessionErrorDomain,
              error.code == ASWebAuthenticationSessionError.canceledLogin.rawValue else { return false }
        return error.localizedDescription.contains("Associated Domains")
    }

    private static func result(for request: MoolreCheckoutRequest, callbackURL: URL?, error: Error?) -> MoolreCheckoutResult {
        if let callbackURL {
            return request.result(forCallback: callbackURL)
        }
        if let authError = error as? ASWebAuthenticationSessionError, authError.code == .canceledLogin {
            return .cancelled
        }
        return .failed(
            code: MoolreErrorCode.launchFailed,
            message: error?.localizedDescription ?? "Checkout ended without a redirect."
        )
    }

    private static func keyWindow() -> ASPresentationAnchor? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let activeScene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        return activeScene?.windows.first(where: \.isKeyWindow) ?? activeScene?.windows.first
    }
}

extension MoolreWebCheckout: ASWebAuthenticationPresentationContextProviding {
    nonisolated public func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            anchorProvider() ?? ASPresentationAnchor()
        }
    }
}
#endif

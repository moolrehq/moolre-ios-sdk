import Foundation
import MoolreCore

/// Validated checkout URL and redirect contract for one `MoolreCheckoutSession`.
///
/// Use this directly only when presenting checkout with your own browser UI; the SDK's
/// `MoolreWebCheckout` applies the same rules.
public struct MoolreCheckoutRequest: Equatable, Sendable {
    public let checkoutURL: URL
    public let redirectURL: URL
    public let expectedReferences: Set<String>

    /// Scheme `ASWebAuthenticationSession` should intercept.
    public var callbackScheme: String { redirectURL.scheme!.lowercased() }

    /// - Throws: `MoolrePaymentError` with `INVALID_CHECKOUT_URL` or `INVALID_REDIRECT_URL`.
    public init(session: MoolreCheckoutSession) throws {
        guard let checkoutURL = URL(string: session.authorizationURL),
              checkoutURL.scheme?.lowercased() == "https",
              !(checkoutURL.host ?? "").isEmpty else {
            throw MoolrePaymentError(
                code: MoolreErrorCode.invalidCheckoutURL,
                message: "Checkout URL must use HTTPS and include a host."
            )
        }
        guard let redirectURL = URL(string: session.redirectURL),
              !(redirectURL.scheme ?? "").isEmpty,
              !(redirectURL.host ?? "").isEmpty else {
            throw MoolrePaymentError(
                code: MoolreErrorCode.invalidRedirectURL,
                message: "Redirect URL must include a scheme and host."
            )
        }
        self.checkoutURL = checkoutURL
        self.redirectURL = redirectURL
        self.expectedReferences = session.expectedReferences
    }

    /// Scheme, host, port, and path must match the configured redirect.
    public func matchesRedirect(_ url: URL) -> Bool {
        url.scheme?.lowercased() == redirectURL.scheme?.lowercased() &&
            url.host?.lowercased() == redirectURL.host?.lowercased() &&
            url.port == redirectURL.port &&
            url.path == redirectURL.path
    }

    /// Maps the URL checkout redirected to into a checkout result.
    ///
    /// The redirect must carry a non-blank `reference` that matches either the merchant
    /// external reference or Moolre's generated reference for this session.
    public func result(forCallback url: URL) -> MoolreCheckoutResult {
        guard matchesRedirect(url) else {
            return .failed(code: MoolreErrorCode.unsupportedRedirect, message: "Checkout redirected to an unsupported URL.")
        }
        let reference = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == "reference" })?
            .value?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let reference, !reference.isEmpty else {
            return .failed(code: MoolreErrorCode.missingReference, message: "Payment reference not found in checkout redirect.")
        }
        if !expectedReferences.isEmpty && !expectedReferences.contains(reference) {
            return .failed(
                code: MoolreErrorCode.referenceMismatch,
                message: "Checkout redirect reference did not match the prepared payment."
            )
        }
        return .completed(reference: reference)
    }
}

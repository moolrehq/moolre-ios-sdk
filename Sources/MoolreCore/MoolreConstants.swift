import Foundation

/// SDK constants shared by every Moolre module.
public enum MoolreConstants {
    public static let livePaymentURL = "https://api.moolre.com/embed/link"
    public static let liveStatusURL = "https://api.moolre.com/open/transact/status"
    public static let sandboxPaymentURL = "https://sandbox.moolre.com/embed/link"
    public static let sandboxStatusURL = "https://sandbox.moolre.com/open/transact/status"
    public static let defaultCallbackScheme = "moolre"
    public static let defaultCallbackHost = "payment-callback"
    public static let defaultRedirectURL = "\(defaultCallbackScheme)://\(defaultCallbackHost)"

    // Payment-link request values
    static let paymentLinkType = 1
    static let statusIDTypeExternalReference = 1
}

/// Stable error codes reported through `MoolrePaymentError` and `MoolrePaymentResult.failure`.
public enum MoolreErrorCode {
    public static let invalidConfig = "INVALID_CONFIG"
    public static let invalidAmount = "INVALID_AMOUNT"
    public static let initiationFailed = "INITIATION_FAILED"
    public static let verificationFailed = "VERIFICATION_FAILED"
    public static let userCancelled = "USER_CANCELLED"
    public static let invalidCheckoutURL = "INVALID_CHECKOUT_URL"
    public static let invalidRedirectURL = "INVALID_REDIRECT_URL"
    public static let missingReference = "MISSING_REFERENCE"
    public static let referenceMismatch = "REFERENCE_MISMATCH"
    public static let unsupportedRedirect = "UNSUPPORTED_REDIRECT"
    public static let launchFailed = "LAUNCH_FAILED"
    public static let paymentInProgress = "PAYMENT_IN_PROGRESS"
    public static let duplicateReference = "DUPLICATE_REFERENCE"
    public static let jsonParsingError = "JSON_PARSING_ERROR"
    public static let emptyResponse = "EMPTY_RESPONSE"
    public static let networkOrUnknownError = "NETWORK_OR_UNKNOWN_ERROR"

    /// Code used when a non-JSON body is returned with an HTTP error status, e.g. `HTTP_401`.
    public static func http(_ statusCode: Int) -> String { "HTTP_\(statusCode)" }
}

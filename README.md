# Moolre iOS SDK

Moolre iOS SDK V1 provides hosted Moolre checkout for iOS applications using
either UIKit or SwiftUI. Both entry points share the same payment-link,
`ASWebAuthenticationSession` checkout, and transaction-verification
implementation. It is the iOS counterpart of the Moolre Android SDK and follows
the same API contract, error codes, and verification policy.

## Requirements

- iOS 15 or newer
- Swift 5.9 / Xcode 15 or newer
- A Moolre API user and account number; a public key is required for LIVE

## Installation

Add the package with Swift Package Manager (**File → Add Package
Dependencies…** in Xcode) or in `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/moolrehq/moolre-ios-sdk.git", from: "1.0.0")
],
targets: [
    .target(name: "YourApp", dependencies: [
        // UIKit application
        .product(name: "MoolreUIKit", package: "moolre-ios-sdk"),
        // Or SwiftUI application
        .product(name: "MoolreSwiftUI", package: "moolre-ios-sdk")
    ])
]
```

Each UI product re-exports `MoolreCore` and `MoolreCheckout`, so a single
`import MoolreUIKit` or `import MoolreSwiftUI` is enough. The repository URL
above assumes the package has been published; while developing, add it as a
local package.

## Example application

`Examples/MoolreExample` is one app with two tabs:

- **SwiftUI**: cart checkout with the branded SwiftUI `MoolrePayButton`.
- **UIKit**: amount/email form with the UIKit `MoolrePayButton` control.

The Xcode project is generated with [XcodeGen](https://github.com/yonaskolb/XcodeGen):

```sh
brew install xcodegen
cd Examples/MoolreExample
cp Config/Credentials.example.xcconfig Config/Credentials.xcconfig
# edit Config/Credentials.xcconfig
xcodegen generate
open MoolreExample.xcodeproj
```

### Configure credentials for the example

`Config/Credentials.xcconfig` is the iOS equivalent of the Android samples'
`local.properties`. It is git-ignored; the build copies its values into the
app's Info.plist:

```
MOOLRE_ENVIRONMENT = SANDBOX
MOOLRE_API_USER = your-moolre-username
MOOLRE_PUBLIC_KEY =
MOOLRE_ACCOUNT_NUMBER = your-sandbox-account-number
```

| Setting | Meaning |
| --- | --- |
| `MOOLRE_ENVIRONMENT` | `SANDBOX` or `LIVE`; controls payment-link and status endpoints |
| `MOOLRE_API_USER` | Moolre API user for the selected environment |
| `MOOLRE_PUBLIC_KEY` | Optional in SANDBOX; required public API key in LIVE |
| `MOOLRE_ACCOUNT_NUMBER` | Moolre account/wallet number for the selected environment |

A pre-build script (`scripts/validate-sample-credentials.sh`) stops the build
when credentials are missing, still placeholders, or the environment is
invalid. It prints only setting names, never values. A sandbox public key may
be blank; a placeholder key is still rejected.

To test production, change the environment and every credential together.
Never mix sandbox and live credentials, references, or API responses. Never
commit `Credentials.xcconfig` or paste real credentials into Swift files,
README files, screenshots, or issue reports.

## Environment selection

The SDK defaults to `.sandbox` so a new integration cannot accidentally create
live payments:

| Environment | Payment-link endpoint | Status endpoint |
| --- | --- | --- |
| `.sandbox` | `https://sandbox.moolre.com/embed/link` | `https://sandbox.moolre.com/open/transact/status` |
| `.live` | `https://api.moolre.com/embed/link` | `https://api.moolre.com/open/transact/status` |

Requests send `X-API-USER` in both environments and include `X-API-PUBKEY`
only when a nonblank key is configured. LIVE requires a public key.

## Payment flow

1. Create a `MoolrePaymentRequest` with a positive amount and customer email.
   Omit `reference` for a fresh SDK-generated external reference, or provide a
   unique merchant order reference.
2. The SDK posts a payment-link request and receives an authorization URL.
3. Checkout opens that HTTPS URL in an `ASWebAuthenticationSession` browser
   sheet.
4. Moolre redirects to the configured `redirectURL` with a `reference`. The
   session catches the redirect and closes. An optional `webhookURL` receives
   the server-side callback.
5. The SDK verifies the original merchant external reference with the matching
   environment's status API.

The V1 client reports success only when the status response envelope is
`status == 1`, the transaction status is successful, and the verified
`externalref` exactly matches the original payment request. The checkout
redirect may carry either the merchant external reference or Moolre's
generated transaction reference; both are checked against the prepared
session. The client does not compare amount or currency. Your server should
still validate the expected amount, currency, account ownership, and order
state before fulfilment.

If the status endpoint reports a successful request with a pending transaction,
the coordinator checks up to three times with a short delay before returning
`VERIFICATION_FAILED`. Network and authentication errors are returned
immediately.

## Configuration

```swift
import MoolreSwiftUI // or MoolreUIKit

let config = try MoolreConfig(
    environment: .sandbox,
    apiUser: "your-moolre-username",
    publicKey: "", // optional in SANDBOX; required in LIVE
    accountNumber: "your-account-number",
    webhookURL: "https://merchant.example.com/moolre/webhook",
    redirectURL: "yourapp://payment-callback"
)
```

`MoolreConfig` and `PaymentParams` throw a `MoolrePaymentError` with code
`INVALID_CONFIG` (or `INVALID_AMOUNT`) when a required value is missing.

### Redirect URL

`redirectURL` defaults to `moolre://payment-callback` and must contain a
scheme and host. Use a scheme unique to your app (for example
`yourapp-moolre://payment-callback`).

Unlike Android, **no host-app registration is needed**. You don't need
`CFBundleURLTypes` or an `AppDelegate`/`SceneDelegate` URL handler, because
`ASWebAuthenticationSession` intercepts the callback scheme itself. Don't also
register the same scheme in your Info.plist for another purpose.

An `https://` redirect is intercepted on iOS 17.4+ only, and only when the app
has an associated domain (`webcredentials` service) for that host. Otherwise
checkout still opens but cannot close itself: the customer closes it after
paying, and the SDK confirms the payment with the status API before reporting
success. Custom schemes work on every supported iOS version.

LIVE accepts only public HTTPS redirects, so in LIVE the SDK leaves a
custom-scheme `redirectURL` out of the payment-link request. Checkout then
closes itself through status polling: while checkout is open, the SDK checks
the payment status every few seconds and closes checkout as soon as the
gateway reports the payment successful.

The redirect is accepted only when its scheme, host, port, and path match
`redirectURL` and its `reference` query parameter matches the prepared
session. A spoofed redirect with a different reference fails with
`REFERENCE_MISMATCH`.

### `MoolrePaymentRequest`

- `amount`: positive `Decimal` in major currency units. Build it from a string,
  `Decimal(string: "25.00")`, not from a `Double`.
- `currency`: currency code, default `GHS`.
- `email`: required customer email.
- `reference`: optional merchant reference. When omitted or blank, the SDK
  generates one `moolre-<uuid>` reference and reuses it while retrying a failed
  initiation of the same attempt. A supplied reference is preserved and must
  be unique.
- `webhookURL` / `redirectURL`: optional per-payment overrides.
- `reusable`: whether the payment link can be reused, default `false`.
- `expirationTimeMinutes`: optional expiry, minimum `1`.
- `metadata`: optional string key/value data.

## UIKit integration

```swift
import MoolreUIKit

let payButton = MoolrePayButton()
payButton.environment = .sandbox
payButton.apiUser = "your-moolre-username"
payButton.publicKey = "your-public-key"
payButton.accountNumber = "your-account-number"
payButton.amount = Decimal(string: "25.00")!
payButton.currency = "GHS"
payButton.email = "customer@example.com"
payButton.webhookURL = "https://merchant.example.com/moolre/webhook"
payButton.redirectURL = "yourapp://payment-callback"
payButton.showsAmount = true

payButton.onPaymentSuccess = { reference in
    // Refresh and fulfil the matching order on your backend.
}
payButton.onPaymentError = { code, message in
    // Map code to app copy and log diagnostics safely.
    // Cancellation is reported here with code USER_CANCELLED.
}
```

The button is a `UIButton` subclass. Add it in code or in Interface Builder
(set the class to `MoolrePayButton` and module to `MoolreUIKit`).
Inspectable properties include `apiUser`, `publicKey`, `accountNumber`,
`amountText`, `currency`, `email`, `reference`, `webhookURL`, `redirectURL`,
`isLiveEnvironment`, `buttonTitle`, `showsAmount`, `showsLogo`,
`buttonTextColor`, `buttonBackgroundColor`, `buttonBorderColor`,
`buttonBorderWidth`, and `buttonCornerRadius`. `onPaymentResult` delivers the
full `MoolrePaymentResult` if you prefer one callback. Call `startPayment()` to
begin checkout programmatically.

The button shows an activity indicator and ignores taps while initiation,
checkout, or verification runs.

## SwiftUI integration

```swift
import MoolreSwiftUI

struct CheckoutButton: View {
    let config: MoolreConfig
    @State private var result: MoolrePaymentResult?

    var body: some View {
        VStack {
            MoolrePayButton(
                config: config,
                payment: MoolrePaymentRequest(
                    amount: Decimal(string: "25.00")!,
                    currency: "GHS",
                    email: "customer@example.com"
                ),
                showAmount: true,
                onResult: { result = $0 }
            )

            switch result {
            case .success(let reference, _): Text("Payment verified: \(reference)")
            case .cancelled: Text("Payment cancelled.")
            case .failure(let code, let message): Text("Payment failed (\(code)): \(message)")
            case nil: EmptyView()
            }
        }
        .moolreTheme()
    }
}
```

Override `containerColor`, `contentColor`, `borderColor`, `borderWidth`,
`cornerRadius`, or `text` to restyle the button. The defaults match the
Android SDK: white background, black content, a 1pt `#FDB93C` border, and a
light-grey disabled background. `MoolreTheme` exposes the brand colors, and
`.moolreTheme()` applies the Moolre tint.

### Custom UI

To drive checkout from your own controls, use `MoolrePaymentLauncher` (an
`ObservableObject` with `isProcessing`):

```swift
@StateObject private var launcher = MoolrePaymentLauncher()

Button("Pay") {
    Task {
        let result = await launcher.launch(request, config: config)
    }
}
.disabled(launcher.isProcessing)
```

## Results and security

Both integrations report `MoolrePaymentResult.success(reference:verification:)`,
`.cancelled`, or `.failure(code:message:)`. Common codes include
`INVALID_CONFIG`, `INVALID_AMOUNT`, `INITIATION_FAILED`, `VERIFICATION_FAILED`,
`USER_CANCELLED`, `MISSING_REFERENCE`, `REFERENCE_MISMATCH`,
`UNSUPPORTED_REDIRECT`, `INVALID_CHECKOUT_URL`, `INVALID_REDIRECT_URL`,
`LAUNCH_FAILED`, `DUPLICATE_REFERENCE`, and `PAYMENT_IN_PROGRESS`. Constants
are available on `MoolreErrorCode`.

Initiation and verification keep valid API error codes and messages together
with the HTTP status. A non-JSON HTTP error returns `HTTP_<status>` (for
example `HTTP_401`), not `JSON_PARSING_ERROR`. Empty successful responses
return `EMPTY_RESPONSE`, and malformed successful responses return
`JSON_PARSING_ERROR`. When PHP diagnostics precede a JSON envelope with an
explicit failure status, the SDK surfaces that API failure, including on HTTP
200. It never accepts a success payload that has warning output in front of
it. Raw response bodies and PHP warning paths are kept out of SDK error
messages.

Treat error messages as diagnostics, not stable UI copy. Never treat a browser
redirect as proof of payment. Keep the order pending until your backend
verifies the reference and checks amount, currency, account number, and order
state. Make fulfilment idempotent, and do not log private credentials or full
payment payloads in release builds. Debug builds log the opened
`authorization_url` to the unified log (subsystem `com.moolre.sdk`, category
`MoolreCheckout`) with private redaction.

An iOS app binary can be inspected by its user. For production, prefer a
backend-owned payment initiation and verification flow, or server-side
injection of credentials.

## Advanced usage

```swift
import MoolreCore

let coordinator = MoolrePaymentCoordinator(gateway: MoolrePaymentService())
let params = try PaymentParams(
    amount: Decimal(string: "25.00")!,
    environment: .sandbox,
    apiUser: "your-moolre-username",
    publicKey: "your-public-key",
    accountNumber: "your-account-number",
    email: "customer@example.com",
    reference: "order-1001",
    callback: "https://merchant.example.com/moolre/webhook",
    redirect: "yourapp://payment-callback"
)

let session = try await coordinator.initiatePayment(params)
// Present session.authorizationURL with MoolreWebCheckout or your own UI, then:
let result = await coordinator.verifyPayment(params, redirectReference: referenceFromCheckout)
```

`MoolreWebCheckout().present(session)` returns a `MoolreCheckoutResult`. To use
your own browser UI, validate redirects with
`MoolreCheckoutRequest(session:).result(forCallback:)`. Inject a custom
`MoolrePaymentGateway` into the coordinator, or a custom
`MoolreCheckoutPresenting` into `MoolrePaymentLauncher`, for tests or an
application-owned transport.

## Testing

```sh
swift test   # core + checkout unit tests, runs on macOS
xcodebuild build -scheme MoolreSDK-Package -destination 'generic/platform=iOS'
```

Before production, test success, cancellation, network failure, missing
references, and mismatched references in sandbox.

## Modules

| Product | Purpose | Android equivalent |
| --- | --- | --- |
| `MoolreCore` | Models, gateway, URLSession payment-link service, verification coordinator | `android-sdk-core` |
| `MoolreCheckout` | `ASWebAuthenticationSession` checkout, redirect validation, shared `MoolrePaymentLauncher` | `android-sdk-checkout` |
| `MoolreUIKit` | UIKit `MoolrePayButton` | `android-sdk-views` |
| `MoolreSwiftUI` | SwiftUI `MoolrePayButton` and `MoolreTheme` | `android-sdk-compose` |

Most applications should depend on `MoolreUIKit` or `MoolreSwiftUI`, not the
lower-level products directly.

## Related documentation

- [Moolre Android SDK](../moolre-android-sdk/README.md)
- [Moolre PHP SDK](https://github.com/moolrehq/moolre-php)

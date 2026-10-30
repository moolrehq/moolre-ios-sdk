#if canImport(UIKit)
import UIKit
@_exported import MoolreCheckout
@_exported import MoolreCore

/// Branded UIKit payment button backed by the shared Moolre checkout flow.
///
/// Set the merchant and payment properties in code or Interface Builder, then observe
/// `onPaymentSuccess` / `onPaymentError` (or `onPaymentResult`). Tapping the button prepares
/// the payment link, presents checkout, and verifies the redirect reference.
@MainActor
open class MoolrePayButton: UIButton {

    // MARK: Payment properties

    public var environment: MoolreEnvironment = .sandbox
    @IBInspectable public var apiUser: String = ""
    @IBInspectable public var publicKey: String = ""
    @IBInspectable public var accountNumber: String = ""
    public var amount: Decimal = 0 { didSet { setNeedsUpdateConfiguration() } }
    @IBInspectable public var currency: String = "GHS" { didSet { setNeedsUpdateConfiguration() } }
    @IBInspectable public var email: String?
    @IBInspectable public var reference: String?
    @IBInspectable public var webhookURL: String?
    @IBInspectable public var redirectURL: String?
    public var reusable = false
    public var expirationTimeMinutes: Int?
    public var metadata: [String: String] = [:]

    /// Interface Builder bridge for `environment`.
    @IBInspectable public var isLiveEnvironment: Bool {
        get { environment == .live }
        set { environment = newValue ? .live : .sandbox }
    }

    /// Interface Builder bridge for `amount`, e.g. `"25.00"`.
    @IBInspectable public var amountText: String {
        get { NSDecimalNumber(decimal: amount).stringValue }
        set { amount = Decimal(string: newValue, locale: Locale(identifier: "en_US_POSIX")) ?? 0 }
    }

    // MARK: Appearance

    @IBInspectable public var buttonTitle: String = MoolreBrand.defaultButtonTitle { didSet { setNeedsUpdateConfiguration() } }
    @IBInspectable public var showsAmount: Bool = false { didSet { setNeedsUpdateConfiguration() } }
    @IBInspectable public var showsLogo: Bool = true { didSet { setNeedsUpdateConfiguration() } }
    @IBInspectable public var buttonTextColor: UIColor = MoolreBrand.buttonContent { didSet { setNeedsUpdateConfiguration() } }
    @IBInspectable public var buttonBackgroundColor: UIColor = MoolreBrand.buttonBackground { didSet { setNeedsUpdateConfiguration() } }
    @IBInspectable public var buttonBorderColor: UIColor = MoolreBrand.orange { didSet { setNeedsUpdateConfiguration() } }
    @IBInspectable public var buttonBorderWidth: CGFloat = 1 { didSet { setNeedsUpdateConfiguration() } }
    @IBInspectable public var buttonCornerRadius: CGFloat = 10 { didSet { setNeedsUpdateConfiguration() } }

    // MARK: Callbacks

    /// Called with the verified external reference.
    public var onPaymentSuccess: ((_ reference: String) -> Void)?
    /// Called for failures and cancellation (`USER_CANCELLED`).
    public var onPaymentError: ((_ code: String, _ message: String) -> Void)?
    /// Called with every final result, in addition to the success/error callbacks.
    public var onPaymentResult: ((MoolrePaymentResult) -> Void)?

    public private(set) var isProcessing = false { didSet { setNeedsUpdateConfiguration() } }

    private lazy var launcher = MoolrePaymentLauncher(checkout: MoolreWebCheckout { [weak self] in self?.window })

    // MARK: Init

    public override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    /// Creates a button that uses a custom launcher, e.g. one with a test gateway or presenter.
    public convenience init(launcher: MoolrePaymentLauncher) {
        self.init(frame: .zero)
        self.launcher = launcher
    }

    private func commonInit() {
        configuration = .plain()
        configurationUpdateHandler = { button in
            (button as? MoolrePayButton)?.applyConfiguration()
        }
        addAction(UIAction { [weak self] _ in self?.startPayment() }, for: .primaryActionTriggered)
    }

    open override var intrinsicContentSize: CGSize {
        let size = super.intrinsicContentSize
        return CGSize(width: size.width, height: max(size.height, 48))
    }

    // MARK: Payment

    /// Starts checkout programmatically. Ignored while a payment is already in progress.
    public func startPayment() {
        guard !isProcessing else { return }
        let config: MoolreConfig
        do {
            config = try MoolreConfig(
                environment: environment,
                apiUser: apiUser,
                publicKey: publicKey,
                accountNumber: accountNumber,
                webhookURL: webhookURL,
                redirectURL: redirectURL ?? MoolreConstants.defaultRedirectURL
            )
        } catch {
            let mapped = error as? MoolrePaymentError
            deliver(.failure(
                code: mapped?.code ?? MoolreErrorCode.invalidConfig,
                message: mapped?.message ?? "Payment configuration is invalid."
            ))
            return
        }

        let request = MoolrePaymentRequest(
            amount: amount,
            currency: currency,
            email: email ?? "",
            reference: reference,
            webhookURL: webhookURL,
            redirectURL: redirectURL,
            reusable: reusable,
            expirationTimeMinutes: expirationTimeMinutes,
            metadata: metadata
        )

        isProcessing = true
        Task { [weak self] in
            guard let self else { return }
            let result = await launcher.launch(request, config: config)
            isProcessing = false
            deliver(result)
        }
    }

    private func deliver(_ result: MoolrePaymentResult) {
        switch result {
        case .success(let reference, _):
            onPaymentSuccess?(reference)
        case .cancelled:
            onPaymentError?(MoolreErrorCode.userCancelled, "Payment was cancelled by the user.")
        case .failure(let code, let message):
            onPaymentError?(code, message)
        }
        onPaymentResult?(result)
    }

    // MARK: Appearance

    private func applyConfiguration() {
        var config = configuration ?? .plain()
        let enabled = isEnabled && !isProcessing

        let title = isProcessing
            ? MoolreBrand.processingButtonTitle
            : MoolreBrand.buttonTitle(buttonTitle, amount: amount, currency: currency, showsAmount: showsAmount)
        config.attributedTitle = AttributedString(NSAttributedString(
            string: title,
            attributes: [.font: UIFont.systemFont(ofSize: 16, weight: .semibold)]
        ))
        config.image = showsLogo ? MoolreBrand.logo : nil
        config.imagePadding = 10
        config.showsActivityIndicator = isProcessing
        config.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16)
        config.baseForegroundColor = enabled ? buttonTextColor : MoolreBrand.buttonDisabledContent

        var background = UIBackgroundConfiguration.clear()
        background.backgroundColor = enabled
            ? (isHighlighted ? buttonBackgroundColor.moolreDarkened() : buttonBackgroundColor)
            : MoolreBrand.buttonDisabledBackground
        background.strokeColor = buttonBorderWidth > 0 ? buttonBorderColor : nil
        background.strokeWidth = buttonBorderWidth
        background.cornerRadius = buttonCornerRadius
        config.background = background
        config.cornerStyle = .fixed

        configuration = config
        alpha = isProcessing ? 0.7 : 1
        isUserInteractionEnabled = !isProcessing
    }
}

private extension UIColor {
    /// Darkens by 20% for the pressed state.
    func moolreDarkened() -> UIColor {
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        guard getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha) else { return self }
        return UIColor(hue: hue, saturation: saturation, brightness: brightness * 0.8, alpha: alpha)
    }
}
#endif

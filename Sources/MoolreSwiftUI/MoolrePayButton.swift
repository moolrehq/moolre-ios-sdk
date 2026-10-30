#if canImport(UIKit)
import SwiftUI
@_exported import MoolreCheckout
@_exported import MoolreCore

/// Branded SwiftUI payment button backed by the shared Moolre checkout flow.
public struct MoolrePayButton: View {
    private let config: MoolreConfig
    private let payment: MoolrePaymentRequest
    private let text: String
    private let showAmount: Bool
    private let containerColor: Color
    private let contentColor: Color
    private let borderColor: Color
    private let borderWidth: CGFloat
    private let cornerRadius: CGFloat
    private let onResult: (MoolrePaymentResult) -> Void

    @StateObject private var launcher: MoolrePaymentLauncher
    @Environment(\.isEnabled) private var isEnabled

    /// - Parameter launcher: Optional custom launcher, e.g. one shared with your own UI or using a
    ///   test gateway. A new SDK launcher is created when omitted.
    public init(
        config: MoolreConfig,
        payment: MoolrePaymentRequest,
        text: String = MoolreBrand.defaultButtonTitle,
        showAmount: Bool = false,
        containerColor: Color = MoolreTheme.buttonBackground,
        contentColor: Color = MoolreTheme.buttonContent,
        borderColor: Color = MoolreTheme.orange,
        borderWidth: CGFloat = 1,
        cornerRadius: CGFloat = 10,
        launcher: MoolrePaymentLauncher? = nil,
        onResult: @escaping (MoolrePaymentResult) -> Void = { _ in }
    ) {
        self.config = config
        self.payment = payment
        self.text = text
        self.showAmount = showAmount
        self.containerColor = containerColor
        self.contentColor = contentColor
        self.borderColor = borderColor
        self.borderWidth = borderWidth
        self.cornerRadius = cornerRadius
        self.onResult = onResult
        _launcher = StateObject(wrappedValue: launcher ?? MoolrePaymentLauncher())
    }

    public var body: some View {
        let enabled = isEnabled && !launcher.isProcessing
        Button {
            Task { onResult(await launcher.launch(payment, config: config)) }
        } label: {
            HStack(spacing: 10) {
                if launcher.isProcessing {
                    ProgressView().tint(contentColor)
                } else if let logo = MoolreBrand.logo {
                    Image(uiImage: logo)
                }
                Text(label)
                    .font(.system(size: 16, weight: .semibold))
            }
            .foregroundColor(enabled ? contentColor : MoolreTheme.buttonDisabledContent)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(enabled ? containerColor : MoolreTheme.buttonDisabledBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(borderColor, lineWidth: borderWidth)
            )
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius))
        }
        .buttonStyle(.plain)
        .disabled(launcher.isProcessing)
        .accessibilityLabel(label)
    }

    private var label: String {
        launcher.isProcessing
            ? MoolreBrand.processingButtonTitle
            : MoolreBrand.buttonTitle(text, amount: payment.amount, currency: payment.currency, showsAmount: showAmount)
    }
}
#endif

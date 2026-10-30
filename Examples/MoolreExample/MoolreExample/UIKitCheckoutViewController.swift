import MoolreUIKit
import SwiftUI
import UIKit

/// UIKit checkout using the `MoolrePayButton` control.
final class UIKitCheckoutViewController: UIViewController {
    private let amountField = UITextField()
    private let emailField = UITextField()
    private let payButton = MoolrePayButton()
    private let resultLabel = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        title = "UIKit Checkout"

        amountField.borderStyle = .roundedRect
        amountField.keyboardType = .decimalPad
        amountField.placeholder = "Amount (GHS)"
        amountField.text = "1.00"
        amountField.addTarget(self, action: #selector(amountChanged), for: .editingChanged)

        emailField.borderStyle = .roundedRect
        emailField.keyboardType = .emailAddress
        emailField.autocapitalizationType = .none
        emailField.placeholder = "Customer email"
        emailField.text = "customer@example.com"
        emailField.addTarget(self, action: #selector(emailChanged), for: .editingChanged)

        resultLabel.numberOfLines = 0
        resultLabel.font = .preferredFont(forTextStyle: .body)

        setupMoolreButton()

        let stack = UIStackView(arrangedSubviews: [amountField, emailField, payButton, resultLabel])
        stack.axis = .vertical
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 32),
            stack.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor)
        ])
    }

    private func setupMoolreButton() {
        let info = Bundle.main.infoDictionary ?? [:]
        payButton.environment = MoolreEnvironment(rawValue: ((info["MoolreEnvironment"] as? String) ?? "").uppercased()) ?? .sandbox
        payButton.apiUser = info["MoolreAPIUser"] as? String ?? ""
        payButton.publicKey = info["MoolrePublicKey"] as? String ?? ""
        payButton.accountNumber = info["MoolreAccountNumber"] as? String ?? ""
        payButton.redirectURL = "moolre-example://payment-callback"
        payButton.currency = "GHS"
        payButton.showsAmount = true
        amountChanged()
        emailChanged()

        payButton.onPaymentSuccess = { [weak self] reference in
            // Refresh and fulfil the matching order on your backend.
            self?.resultLabel.text = "Payment verified: \(reference)"
            self?.resultLabel.textColor = .systemGreen
        }
        payButton.onPaymentError = { [weak self] code, message in
            // Map code to app copy and log diagnostics safely.
            self?.resultLabel.text = "Payment failed (\(code)): \(message)"
            self?.resultLabel.textColor = .systemRed
        }
    }

    @objc private func amountChanged() {
        payButton.amount = Decimal(string: amountField.text ?? "", locale: Locale(identifier: "en_US_POSIX")) ?? 0
    }

    @objc private func emailChanged() {
        payButton.email = emailField.text
    }
}

struct UIKitCheckoutView: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UINavigationController {
        let navigation = UINavigationController(rootViewController: UIKitCheckoutViewController())
        navigation.navigationBar.prefersLargeTitles = true
        return navigation
    }

    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {}
}

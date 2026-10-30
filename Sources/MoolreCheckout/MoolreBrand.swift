#if canImport(UIKit)
import UIKit

/// Moolre brand colors and logo shared by the UIKit and SwiftUI buttons.
public enum MoolreBrand {
    public static let primary = UIColor(red: 0x14 / 255, green: 0x2A / 255, blue: 0x4A / 255, alpha: 1)
    public static let orange = UIColor(red: 0xFD / 255, green: 0xB9 / 255, blue: 0x3C / 255, alpha: 1)
    public static let buttonBackground = UIColor.white
    public static let buttonContent = UIColor.black
    public static let buttonDisabledBackground = UIColor(red: 0xD3 / 255, green: 0xD3 / 255, blue: 0xD3 / 255, alpha: 1)
    public static let buttonDisabledContent = UIColor.black

    public static let defaultButtonTitle = "Pay with Moolre"
    public static let processingButtonTitle = "Processing payment"

    public static var logo: UIImage? {
        UIImage(named: "moolre-logo", in: .module, compatibleWith: nil)
    }

    /// Button label with an optional `• GHS 25.00` amount suffix.
    public static func buttonTitle(_ title: String, amount: Decimal, currency: String, showsAmount: Bool) -> String {
        guard showsAmount, amount > 0 else { return title }
        return "\(title) \u{2022} \(currency) \(formattedAmount(amount))"
    }

    static func formattedAmount(_ amount: Decimal) -> String {
        var value = amount
        var rounded = Decimal()
        NSDecimalRound(&rounded, &value, 2, .plain)
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        formatter.minimumIntegerDigits = 1
        return formatter.string(from: rounded as NSDecimalNumber) ?? "\(rounded)"
    }
}
#endif

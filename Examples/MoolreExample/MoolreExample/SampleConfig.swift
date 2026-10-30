import Foundation
import MoolreCore

/// Reads the sample credentials that the build injects into Info.plist from Credentials.xcconfig.
enum SampleConfig {
    static func make(redirectURL: String) -> Result<MoolreConfig, MoolrePaymentError> {
        let info = Bundle.main.infoDictionary ?? [:]
        let environment = MoolreEnvironment(rawValue: ((info["MoolreEnvironment"] as? String) ?? "").uppercased()) ?? .sandbox
        do {
            return .success(try MoolreConfig(
                environment: environment,
                apiUser: info["MoolreAPIUser"] as? String ?? "",
                publicKey: info["MoolrePublicKey"] as? String ?? "",
                accountNumber: info["MoolreAccountNumber"] as? String ?? "",
                redirectURL: redirectURL
            ))
        } catch let error as MoolrePaymentError {
            return .failure(error)
        } catch {
            return .failure(MoolrePaymentError(code: MoolreErrorCode.invalidConfig, message: error.localizedDescription))
        }
    }
}

extension MoolrePaymentResult {
    var displayText: String {
        switch self {
        case .success(let reference, _): return "Payment verified: \(reference)"
        case .cancelled: return "Payment cancelled before verification."
        case .failure(let code, let message): return "Payment failed (\(code)): \(message)"
        }
    }
}

func formatGHS(_ amount: Decimal) -> String {
    let formatter = NumberFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.minimumFractionDigits = 2
    formatter.maximumFractionDigits = 2
    formatter.minimumIntegerDigits = 1
    return "GHS \(formatter.string(from: amount as NSDecimalNumber) ?? "\(amount)")"
}

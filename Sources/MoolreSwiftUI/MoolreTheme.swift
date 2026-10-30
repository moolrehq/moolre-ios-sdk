#if canImport(UIKit)
import SwiftUI

/// Moolre brand colors for SwiftUI.
public enum MoolreTheme {
    public static let primary = Color(uiColor: MoolreBrand.primary)
    public static let orange = Color(uiColor: MoolreBrand.orange)
    public static let buttonBackground = Color(uiColor: MoolreBrand.buttonBackground)
    public static let buttonContent = Color(uiColor: MoolreBrand.buttonContent)
    public static let buttonDisabledBackground = Color(uiColor: MoolreBrand.buttonDisabledBackground)
    public static let buttonDisabledContent = Color(uiColor: MoolreBrand.buttonDisabledContent)
}

public extension View {
    /// Optional: applies Moolre's brand tint to this view hierarchy.
    func moolreTheme() -> some View {
        tint(MoolreTheme.primary)
    }
}
#endif

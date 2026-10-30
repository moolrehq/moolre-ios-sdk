import SwiftUI

@main
struct MoolreExampleApp: App {
    var body: some Scene {
        WindowGroup {
            TabView {
                SwiftUICheckoutView()
                    .tabItem { Label("SwiftUI", systemImage: "cart") }
                UIKitCheckoutView()
                    .ignoresSafeArea(edges: .top)
                    .tabItem { Label("UIKit", systemImage: "creditcard") }
            }
        }
    }
}

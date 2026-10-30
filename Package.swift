// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MoolreSDK",
    platforms: [
        .iOS(.v15),
        // macOS is declared only so the UI-independent targets can be unit tested with `swift test`.
        .macOS(.v12)
    ],
    products: [
        .library(name: "MoolreUIKit", targets: ["MoolreUIKit"]),
        .library(name: "MoolreSwiftUI", targets: ["MoolreSwiftUI"]),
        .library(name: "MoolreCheckout", targets: ["MoolreCheckout"]),
        .library(name: "MoolreCore", targets: ["MoolreCore"])
    ],
    targets: [
        .target(name: "MoolreCore"),
        .target(name: "MoolreCheckout", dependencies: ["MoolreCore"], resources: [.process("Resources")]),
        .target(name: "MoolreUIKit", dependencies: ["MoolreCore", "MoolreCheckout"]),
        .target(name: "MoolreSwiftUI", dependencies: ["MoolreCore", "MoolreCheckout"]),
        .testTarget(name: "MoolreCoreTests", dependencies: ["MoolreCore"]),
        .testTarget(name: "MoolreCheckoutTests", dependencies: ["MoolreCheckout"])
    ]
)

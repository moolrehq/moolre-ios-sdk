# Changelog

All notable changes to the Moolre iOS SDK are documented here. The SDK follows
[Semantic Versioning](https://semver.org). The Swift package and all four pods
(`MoolreCore`, `MoolreCheckout`, `MoolreUIKit`, `MoolreSwiftUI`) share one
version number.

## [1.0.0] - Unreleased

### Added
- Hosted Moolre checkout through `ASWebAuthenticationSession`.
- Payment-link creation and transaction verification for SANDBOX and LIVE.
- UIKit `MoolrePayButton` (`MoolreUIKit`) and SwiftUI `MoolrePayButton` and
  `MoolreTheme` (`MoolreSwiftUI`).
- Privacy manifest (`PrivacyInfo.xcprivacy`) shipped with `MoolreCore`.
- Distribution through Swift Package Manager and CocoaPods.

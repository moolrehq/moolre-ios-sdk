# Releasing the Moolre iOS SDK

The Swift package and the four pods share one version. Swift Package Manager
reads versions from git tags, and CocoaPods reads the `s.version` in each
podspec and fetches the source at the tag with the same name.

## One-time setup

1. Make `https://github.com/moolrehq/moolre-ios-sdk` public. Both SPM and
   CocoaPods consumers fetch the source from it.
2. Register a CocoaPods trunk session:
   `pod trunk register <maintainer-email> 'Moolre' --description='release machine'`
   and click the link in the confirmation email.
3. After the first push of each pod, add other maintainers:
   `pod trunk add-owner <PodName> <their-email>`.

## Release steps

Use `X.Y.Z` for the new version. Tags use the `vX.Y.Z` format (for example
`v1.0.0`); the podspecs fetch the source from that tag, and Swift Package
Manager reads versions from it.

1. Set `s.version = 'X.Y.Z'` in all four podspecs:

   ```sh
   sed -i '' "s/s.version          = '.*'/s.version          = 'X.Y.Z'/" Moolre*.podspec
   ```

2. Move the `Unreleased` entries in `CHANGELOG.md` under `X.Y.Z` with today's
   date.
3. Validate:

   ```sh
   swift test
   xcodebuild build -scheme MoolreSDK-Package -destination 'generic/platform=iOS'
   pod lib lint MoolreCore.podspec MoolreCheckout.podspec MoolreUIKit.podspec \
     MoolreSwiftUI.podspec --include-podspecs='*.podspec' --platforms=ios
   ```

4. Commit, tag, and push:

   ```sh
   git commit -am "Release X.Y.Z"
   git tag vX.Y.Z
   git push origin main vX.Y.Z
   ```

   The Swift package is published once the tag is on GitHub.

5. Push the pods to trunk in dependency order. Each push waits until the
   previous pod is available (`--synchronous`):

   ```sh
   pod trunk push MoolreCore.podspec --synchronous
   pod trunk push MoolreCheckout.podspec --synchronous
   pod trunk push MoolreUIKit.podspec --synchronous
   pod trunk push MoolreSwiftUI.podspec --synchronous
   ```

6. Create a GitHub release for the tag with the changelog entries.

A tag can't be changed after it is published, so if a step fails after the
push, fix the problem and release a new patch version.

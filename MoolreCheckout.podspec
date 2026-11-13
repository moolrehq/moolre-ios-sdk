Pod::Spec.new do |s|
  s.name             = 'MoolreCheckout'
  s.version          = '1.0.0'
  s.summary          = 'ASWebAuthenticationSession checkout and payment launcher for the Moolre iOS SDK.'
  s.description      = <<-DESC
    The Moolre iOS SDK brings Moolre services to UIKit and SwiftUI apps,
    starting with hosted Moolre checkout for payments. MoolreCheckout is one module of
    the SDK.
  DESC
  s.homepage         = 'https://github.com/moolrehq/moolre-ios-sdk'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'Moolre' => 'https://moolre.com' }
  s.source           = { :git => 'https://github.com/moolrehq/moolre-ios-sdk.git', :tag => "v#{s.version}" }

  s.ios.deployment_target = '15.0'
  s.swift_versions   = ['5.0']
  s.module_name      = 'MoolreCheckout'
  s.source_files     = 'Sources/MoolreCheckout/**/*.swift'
  s.resource_bundles = { 'MoolreCheckout' => ['Sources/MoolreCheckout/Resources/*.png'] }
  s.frameworks       = 'AuthenticationServices', 'UIKit'
  s.dependency 'MoolreCore', s.version.to_s
end
